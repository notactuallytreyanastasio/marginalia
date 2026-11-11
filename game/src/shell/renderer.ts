// The cel-shading engine. WebGL 1, no libraries, so it runs on any phone that
// can run the page at all.
//
// A frame is five passes over the scene the core describes:
//
//   1. shadow  the casters seen from the light, into a depth map that covers a
//              fixed box round the ball. Skipped where the phone cannot keep
//              one; the toon pass then paints a blob under the ball instead.
//   2. sky     a banded gradient behind everything, with flat two-tone clouds
//              drifting across it and halftone dots along the horizon
//   3. toon    each object lit in three flat steps instead of a smooth falloff,
//              a hard highlight and a rim band on the shiny things, and one
//              flat darkening step wherever the shadow map says the light is
//              blocked
//   4. ink     each object again, turned inside out and swollen sideways on
//              screen along its smooth normals, in near-black. Only the rim
//              that pokes out past the lit object survives the depth test, and
//              that rim is the outline.
//   5. specks  particles, as flat camera-facing discs with an inked edge
//
// Every GPU object lives in one bundle that can be thrown away and built
// again, because a phone can take the context away at any moment (a call
// comes in, the tab is backgrounded) and give back a blank one later.

import {mat4TransformPoint} from "../core/math.ts"
import type {Mat4, MeshData, MeshName, Meshes, Pattern, Scene, SceneItem, Vec3} from "../core/types.ts"

export interface Renderer {
  resize(width: number, height: number): void
  draw(scene: Scene): void
  destroy(): void
}

// --- tuning ----------------------------------------------------------------

// Half the width of the square the shadow map covers, in world units, and
// how far the light's eye stands back from the box's centre. The depth range
// is twice that, so a shorter stand-off buys depth precision on phones whose
// shaders only have mediump.
const SHADOW_HALF = 12
const SHADOW_STANDOFF = 16
const SHADOW_SIZE = 1024
// Push the box this far ahead of the ball, along the way the camera looks,
// since that is where most of what is on screen lies.
const SHADOW_LEAD = 3
// Bias in world units: a little always, and more where the light grazes the
// surface and one texel spans a long stretch of depth.
const SHADOW_BIAS = 0.035
const SHADOW_SLOPE_BIAS = 1.2 * ((2 * SHADOW_HALF) / SHADOW_SIZE)

// The core gives outline widths as a fraction of depth, 0.0036 for most
// things. The ink follows the size of the picture: 0.0036 comes to about
// 1.3% of the screen's short side, which is about 1.8 CSS pixels on a phone.
// CSS pixels alone are not enough, because a page shown without a viewport
// tag is laid out 980 pixels wide and shrunk to fit, which would thin the
// lines to nothing; so the screen decides, kept between 1.8 and 3.6 CSS
// pixels so a big desktop window does not get felt-tip lines.
const OUTLINE_SCREEN_FRACTION = 1.3
const OUTLINE_MIN_CSS = 1.8 / 0.0036
const OUTLINE_MAX_CSS = 3.6 / 0.0036

// --- shaders ---------------------------------------------------------------

const LIT_VERTEX = `
attribute vec3 aPosition;
attribute vec3 aNormal;

uniform mat4 uViewProjection;
uniform mat4 uModel;
uniform vec3 uScale;

varying vec3 vWorld;
varying vec3 vNormal;
varying vec3 vLocal;

#ifdef SHADOWS
uniform mat4 uLightMatrix;
varying vec3 vShadow;
#endif

void main() {
  vec4 world = uModel * vec4(aPosition * uScale, 1.0);
  vWorld = world.xyz;
  // dividing by the scale is the inverse transpose of a scaled rotation
  vNormal = mat3(uModel) * (aNormal / uScale);
  vLocal = aPosition;
#ifdef SHADOWS
  // orthographic, so no divide: just from -1..1 to 0..1
  vShadow = (uLightMatrix * world).xyz * 0.5 + 0.5;
#endif
  gl_Position = uViewProjection * world;
}
`

const LIT_FRAGMENT = `
#ifdef DERIVATIVES
#extension GL_OES_standard_derivatives : enable
#endif
precision mediump float;

// Shadow lookups need more than mediump where it is to be had: a 1024 texel
// map addressed at mediump lands on the wrong texel, and depth compared at
// mediump needs a bias big enough to lift shadows off their casters. The
// paper grid needs it too: phones run mediump as half floats, whose step is
// already 0.03 by 32 m out, as wide as a grid line, so far down a long stage
// the lines would come out in blocks.
#if defined(GL_FRAGMENT_PRECISION_HIGH)
#define SHADOWP highp
#else
#define SHADOWP mediump
#endif

uniform vec3 uColor;
uniform vec3 uColor2;
uniform vec3 uColor3;
uniform float uPattern;
uniform float uRim;
uniform vec3 uLight;
uniform vec3 uEye;
uniform vec4 uBall;

varying SHADOWP vec3 vWorld;
varying vec3 vNormal;
varying vec3 vLocal;

#ifdef SHADOWS
uniform sampler2D uShadowMap;
// x: texels across, y: constant bias, z: slope bias (both in depth units)
uniform SHADOWP vec3 uShadowInfo;
varying SHADOWP vec3 vShadow;
#endif

const float DARK = 0.58;
const vec3 RIM = vec3(1.0, 0.97, 0.86);

// About one screen pixel's worth of x, so a band's edge is blended over a
// pixel and does not crawl as the object turns.
float aa(float x) {
#ifdef DERIVATIVES
  return max(fwidth(x) * 0.75, 0.0005);
#else
  return 0.015;
#endif
}

float band(float edge, float x) {
  float w = aa(x);
  return smoothstep(edge - w, edge + w, x);
}

// The coordinate comes in at full precision and is wrapped before anything
// else is done with it; what is left is small enough for mediump.
float gridLine(SHADOWP float coordinate, float spacing, float width) {
  float d = abs(fract(coordinate / spacing + 0.5) - 0.5) * spacing;
  return 1.0 - smoothstep(width, width * 2.2, d);
}

#ifdef SHADOWS
SHADOWP float depthAt(SHADOWP vec2 uv) {
#ifdef PACKED
  SHADOWP vec4 p = texture2D(uShadowMap, uv);
  return dot(p, vec4(1.0, 1.0 / 255.0, 1.0 / 65025.0, 1.0 / 16581375.0));
#else
  return texture2D(uShadowMap, uv).r;
#endif
}

// 0 in the light, 1 in shadow.
float shadowAt(float lit) {
  SHADOWP vec3 c = vShadow;
  if (c.x < 0.0 || c.x > 1.0 || c.y < 0.0 || c.y > 1.0 || c.z > 1.0) return 0.0;
  float slope = min(sqrt(max(1.0 - lit * lit, 0.0)) / max(lit, 0.1), 8.0);
  SHADOWP float z = c.z - uShadowInfo.y - uShadowInfo.z * slope;
#if defined(GL_FRAGMENT_PRECISION_HIGH)
  // Four comparisons blended by where this point falls between their
  // texels, then cut at one half: still a hard edge, but one that follows a
  // smooth curve instead of the texel staircase.
  SHADOWP vec2 t = c.xy * uShadowInfo.x - 0.5;
  SHADOWP vec2 f = fract(t);
  SHADOWP vec2 base = (floor(t) + 0.5) / uShadowInfo.x;
  SHADOWP float texel = 1.0 / uShadowInfo.x;
  float s00 = step(depthAt(base), z);
  float s10 = step(depthAt(base + vec2(texel, 0.0)), z);
  float s01 = step(depthAt(base + vec2(0.0, texel)), z);
  float s11 = step(depthAt(base + vec2(texel, texel)), z);
  float s = mix(mix(s00, s10, f.x), mix(s01, s11, f.x), f.y);
  return band(0.5, s);
#else
  return step(depthAt(c.xy), z);
#endif
}
#endif

void main() {
  vec3 n = normalize(vNormal);
  vec3 base = uColor;
  float gloss = 0.0;

  if (uPattern > 1.5) {
    // the ball: two halves and a pale belt, so its spin can be read
    base = vLocal.y > 0.0 ? uColor : uColor3;
    base = mix(base, uColor2, step(abs(vLocal.y), 0.2));
    gloss = 1.0;
  } else if (uPattern > 0.5) {
    // a sheet of squared paper on top, cut edges round the sides
    if (n.y > 0.5) {
      float fade = 1.0 - smoothstep(18.0, 60.0, distance(vWorld, uEye));
      float fine = max(gridLine(vWorld.x, 1.0, 0.018), gridLine(vWorld.z, 1.0, 0.018));
      float bold = max(gridLine(vWorld.x, 4.0, 0.035), gridLine(vWorld.z, 4.0, 0.035));
      base = mix(base, uColor2, max(fine * 0.45, bold) * fade);
    } else {
      base = uColor3;
    }
  }

  // three flat steps of light
  float lit = dot(n, uLight);
  float shade = DARK + 0.22 * band(-0.05, lit) + 0.2 * band(0.45, lit);

#ifdef SHADOWS
  // Faces turned from the light are already in the darkest step, and testing
  // them would only invite acne on the far side of the casters.
  if (lit > -0.1) shade = mix(shade, min(shade, DARK), shadowAt(lit));
#else
  // no shadow map: the ball's shadow straight down onto whatever is below it
  vec3 below = vWorld - uBall.xyz;
  if (uPattern < 1.5 && n.y > 0.3 && below.y < -0.2 && below.y > -14.0) {
    float radius = uBall.w * (1.0 + below.y * 0.035);
    if (length(below.xz) < radius) shade = min(shade, DARK);
  }
#endif

  vec3 color = base * shade;
  vec3 toEye = normalize(uEye - vWorld);

  if (uRim > 0.5) {
    // a thin lit band round the silhouette on the side the light is on
    float rim = 1.0 - max(dot(n, toEye), 0.0);
    float strength = band(0.68, rim) * smoothstep(-0.3, 0.1, lit + 0.25);
    color = mix(color, RIM, strength * 0.6);
  }

  if (gloss > 0.0) {
    float highlight = dot(n, normalize(uLight + toEye));
    color = mix(color, vec3(1.0), band(0.965, highlight) * 0.85);
  }

  gl_FragColor = vec4(color, 1.0);
}
`

const INK_VERTEX = `
attribute vec3 aPosition;
attribute vec3 aSmooth;

uniform mat4 uViewProjection;
uniform mat4 uModel;
uniform vec3 uScale;
// in device pixels
uniform vec2 uViewport;
uniform float uWidth;

void main() {
  vec4 world = uModel * vec4(aPosition * uScale, 1.0);
  vec4 clip = uViewProjection * world;

  // Where the smooth normal points once it is on screen, found by projecting
  // a point a short way along it. Pushing out sideways on screen, rather
  // than along the normal in the world, gives the same width of line on a
  // thin ring as on a wide floor, near or far, at any pixel ratio.
  vec3 n = normalize(mat3(uModel) * aSmooth);
  vec4 ahead = uViewProjection * vec4(world.xyz + n * 0.01 * max(clip.w, 0.1), 1.0);
  if (clip.w > 0.0 && ahead.w > 0.0) {
    vec2 d = (ahead.xy / ahead.w - clip.xy / clip.w) * uViewport;
    float len = length(d);
    if (len > 1e-6) clip.xy += (d / len) * (2.0 * uWidth / uViewport) * clip.w;
  }
  gl_Position = clip;
}
`

const INK_FRAGMENT = `
precision mediump float;
void main() {
  gl_FragColor = vec4(0.11, 0.09, 0.13, 1.0);
}
`

const CASTER_VERTEX = `
attribute vec3 aPosition;
uniform mat4 uLightMatrix;
uniform mat4 uModel;
uniform vec3 uScale;
void main() {
  gl_Position = uLightMatrix * (uModel * vec4(aPosition * uScale, 1.0));
}
`

// With a depth texture the depth buffer is the map, and colour is ignored.
const CASTER_DEPTH_FRAGMENT = `
precision mediump float;
void main() {
  gl_FragColor = vec4(1.0);
}
`

// Without one, depth is spread over the four bytes of a colour, 8 bits each.
// Only built where highp exists; mediump cannot hold the low bytes.
const CASTER_PACKED_FRAGMENT = `
precision highp float;
void main() {
  vec4 p = fract(gl_FragCoord.z * vec4(1.0, 255.0, 65025.0, 16581375.0));
  p -= p.yzww * vec4(1.0 / 255.0, 1.0 / 255.0, 1.0 / 255.0, 0.0);
  gl_FragColor = p;
}
`

// The sky is drawn in three passes over as few pixels as each needs: flat
// bands over the whole screen, halftone dots over the bottom strip only, and
// each cloud over its own small box. A shader that did all three for every
// pixel cost more than the whole stage under a software rasteriser, which
// runs both sides of every branch and so gains nothing from early outs.
const SKY_VERTEX = `
attribute vec2 aCorner;
// the part of the screen to cover, as x0, y0, x1, y1 in 0..1
uniform vec4 uRect;
varying vec2 vUv;
void main() {
  vUv = mix(uRect.xy, uRect.zw, aCorner * 0.5 + 0.5);
  // On the far plane: drawn after the stage with the depth test on, it only
  // shades pixels nothing else covered.
  gl_Position = vec4(vUv * 2.0 - 1.0, 1.0, 1.0);
}
`

const SKY_FRAGMENT = `
#ifdef GL_FRAGMENT_PRECISION_HIGH
// the halftone grid is counted in pixels, which mediump cannot count far
precision highp float;
#else
precision mediump float;
#endif

uniform vec3 uTop;
uniform vec3 uBottom;
// x: width / height, y: screen height in device pixels, z: device pixels per CSS pixel
uniform vec3 uScreen;
varying vec2 vUv;

vec3 banded() {
  float bands = 7.0;
  float t = floor(vUv.y * bands) / (bands - 1.0);
  return mix(uBottom, uTop, clamp(t, 0.0, 1.0));
}

#ifdef CLOUD
const vec3 INK = vec3(0.11, 0.09, 0.13);
// x, y: where the cloud sits, in screen heights; z: its size
uniform vec3 uCloud;

// A cloud as three overlapping circles sat on a flat base, as a distance
// (negative inside) in units of the screen's height.
float cloud(vec2 p, vec2 at, float size) {
  vec2 q = (p - at) / size;
  float d = length(q - vec2(-0.55, 0.0)) - 0.42;
  d = min(d, length(q - vec2(0.0, 0.16)) - 0.55);
  d = min(d, length(q - vec2(0.58, 0.02)) - 0.38);
  d = max(d, -q.y - 0.2);
  return d * size;
}
#endif

void main() {
#if defined(BANDS)
  gl_FragColor = vec4(banded(), 1.0);
#elif defined(DOTS)
  // Halftone dots growing toward the bottom of the screen: the printed look.
  // The camera looks down on stages floating in the sky, so most of the sky
  // on screen is below the horizon; the dots key off the screen instead.
  float spacing = 7.0 * uScreen.z;
  vec2 grid = vec2(vUv.x * uScreen.x, vUv.y) * uScreen.y / spacing;
  grid = mat2(0.7071, -0.7071, 0.7071, 0.7071) * grid;
  float fromCentre = length(fract(grid) - 0.5) * spacing;
  float amount = 1.0 - smoothstep(0.0, 0.3, vUv.y);
  float radius = spacing * 0.42 * amount;
  float dotMask = 1.0 - smoothstep(radius - 0.75, radius + 0.75, fromCentre);
  dotMask *= step(0.02, amount);
  gl_FragColor = vec4(mix(banded(), mix(uBottom, uTop, 0.35), 0.7), dotMask);
#elif defined(CLOUD)
  float px = 1.0 / uScreen.y;
  vec2 p = vec2(vUv.x * uScreen.x, vUv.y);
  float outer = cloud(p, uCloud.xy, uCloud.z);
  // the same cloud nudged down and left: what it does not cover is the
  // shaded underside
  float lit = cloud(p, uCloud.xy + vec2(-0.06, -0.1) * uCloud.z, uCloud.z);
  vec3 white = mix(vec3(1.0), uTop, 0.06);
  vec3 under = mix(vec3(0.86, 0.88, 0.97), uTop, 0.25);
  float inside = 1.0 - smoothstep(-px, px, outer);
  float sunny = 1.0 - smoothstep(-px, px, max(lit, outer));
  float line = 1.1 * uScreen.z * px;
  float edge = (1.0 - smoothstep(line, line + px, abs(outer))) * 0.85;
  vec3 fill = mix(under, white, sunny);
  float alpha = max(inside, edge);
  gl_FragColor = vec4(mix(fill, INK, alpha > 0.0 ? edge / alpha : 0.0), alpha);
#endif
}
`

const SPECK_VERTEX = `
attribute vec3 aCenter;
attribute vec2 aCorner;
attribute vec4 aColor;
attribute float aSize;

uniform mat4 uViewProjection;
uniform vec3 uRight;
uniform vec3 uUp;

varying vec2 vCorner;
varying vec4 vColor;

void main() {
  vCorner = aCorner;
  vColor = aColor;
  vec3 p = aCenter + (uRight * aCorner.x + uUp * aCorner.y) * (aSize * 0.5);
  gl_Position = uViewProjection * vec4(p, 1.0);
}
`

const SPECK_FRAGMENT = `
#ifdef DERIVATIVES
#extension GL_OES_standard_derivatives : enable
#endif
precision mediump float;
varying vec2 vCorner;
varying vec4 vColor;
void main() {
  float d = length(vCorner);
#ifdef DERIVATIVES
  float w = max(fwidth(d), 0.02);
#else
  float w = 0.06;
#endif
  float coverage = 1.0 - smoothstep(1.0 - w, 1.0, d);
  if (coverage <= 0.0) discard;
  float ink = smoothstep(0.66 - w, 0.66, d);
  vec3 color = mix(vColor.rgb, vec3(0.11, 0.09, 0.13), ink);
  gl_FragColor = vec4(color, vColor.a * coverage);
}
`

// Which attribute goes in which slot, per program. Fixed slots mean a mesh's
// buffers can be bound the same way whichever program draws them.
const MESH_ATTRIBUTES = ["aPosition", "aNormal", "aSmooth"] as const
const SPECK_ATTRIBUTES = ["aCenter", "aCorner", "aColor", "aSize"] as const
const SLOT_POSITION = 0
const SLOT_NORMAL = 1
const SLOT_SMOOTH = 2
const SPECK_FLOATS = 10
const SPECK_VERTICES = 6
const SPECK_CORNERS: readonly (readonly [number, number])[] = [[-1, -1], [1, -1], [1, 1], [-1, -1], [1, 1], [-1, 1]]

// What the toon shader is told about a pattern; it branches on thresholds
// halfway between these.
const patternCode = (pattern: Pattern): number => {
  switch (pattern) {
    case "plain":
      return 0
    case "paper":
      return 1
    case "ball":
      return 2
    default: {
      const unreachable: never = pattern
      return unreachable
    }
  }
}

// --- owning GPU objects ----------------------------------------------------

// Everything created through a bin is deleted by its release(), so a half
// built set of resources can be dropped as easily as a whole one.
interface Bin {
  buffer(target: GLenum, data: Float32Array | Uint16Array | null): WebGLBuffer
  texture(): WebGLTexture
  framebuffer(): WebGLFramebuffer
  renderbuffer(): WebGLRenderbuffer
  program(vertex: string, fragment: string, attributes: readonly string[]): WebGLProgram
  // take over another bin's objects, to be released along with this one's
  adopt(other: Bin): void
  release(): void
}

const createBin = (gl: WebGLRenderingContext): Bin => {
  const deleters: (() => void)[] = []

  const compile = (type: GLenum, source: string): WebGLShader => {
    const shader = gl.createShader(type)
    if (!shader) throw new Error("shader: could not be created")
    deleters.push(() => gl.deleteShader(shader))
    gl.shaderSource(shader, source)
    gl.compileShader(shader)
    if (gl.getShaderParameter(shader, gl.COMPILE_STATUS) !== true) {
      throw new Error(`shader: ${gl.getShaderInfoLog(shader) ?? "no log"}`)
    }
    return shader
  }

  return {
    buffer(target, data) {
      const b = gl.createBuffer()
      if (!b) throw new Error("buffer: could not be created")
      deleters.push(() => gl.deleteBuffer(b))
      if (data) {
        gl.bindBuffer(target, b)
        gl.bufferData(target, data, gl.STATIC_DRAW)
      }
      return b
    },
    texture() {
      const t = gl.createTexture()
      if (!t) throw new Error("texture: could not be created")
      deleters.push(() => gl.deleteTexture(t))
      return t
    },
    framebuffer() {
      const f = gl.createFramebuffer()
      if (!f) throw new Error("framebuffer: could not be created")
      deleters.push(() => gl.deleteFramebuffer(f))
      return f
    },
    renderbuffer() {
      const r = gl.createRenderbuffer()
      if (!r) throw new Error("renderbuffer: could not be created")
      deleters.push(() => gl.deleteRenderbuffer(r))
      return r
    },
    program(vertex, fragment, attributes) {
      const program = gl.createProgram()
      if (!program) throw new Error("program: could not be created")
      deleters.push(() => gl.deleteProgram(program))
      gl.attachShader(program, compile(gl.VERTEX_SHADER, vertex))
      gl.attachShader(program, compile(gl.FRAGMENT_SHADER, fragment))
      attributes.forEach((name, i) => gl.bindAttribLocation(program, i, name))
      gl.linkProgram(program)
      if (gl.getProgramParameter(program, gl.LINK_STATUS) !== true) {
        throw new Error(`program: ${gl.getProgramInfoLog(program) ?? "no log"}`)
      }
      return program
    },
    adopt(other) {
      deleters.push(() => other.release())
    },
    release() {
      // Deleting from a lost context is a harmless no-op.
      for (const del of deleters.splice(0).reverse()) del()
    },
  }
}

const defines = (flags: readonly string[]): string => flags.map(flag => `#define ${flag}\n`).join("")

// --- the resources of one context ------------------------------------------

interface GpuMesh {
  readonly positions: WebGLBuffer
  readonly normals: WebGLBuffer
  readonly smooth: WebGLBuffer
  readonly indices: WebGLBuffer
  readonly count: number
}

// A location is null where the driver has optimised a uniform away, and
// WebGL ignores writes to null, so a null here is not an error.
type Location = WebGLUniformLocation | null

interface LitProgram {
  readonly program: WebGLProgram
  readonly viewProjection: Location
  readonly model: Location
  readonly scale: Location
  readonly lightMatrix: Location
  readonly color: Location
  readonly color2: Location
  readonly color3: Location
  readonly pattern: Location
  readonly rim: Location
  readonly light: Location
  readonly eye: Location
  readonly ball: Location
  readonly shadowMap: Location
  readonly shadowInfo: Location
}

interface ShadowMap {
  readonly framebuffer: WebGLFramebuffer
  readonly texture: WebGLTexture
  readonly size: number
  // depth units per world unit
  readonly depthScale: number
  // colour must be cleared to "far" when depth is packed into it
  readonly packed: boolean
  readonly program: WebGLProgram
  readonly lightMatrix: Location
  readonly model: Location
  readonly scale: Location
}

interface SkyProgram {
  readonly program: WebGLProgram
  readonly rect: Location
  readonly top: Location
  readonly bottom: Location
  readonly screen: Location
}

interface Gpu {
  readonly bin: Bin
  readonly meshes: ReadonlyMap<MeshName, GpuMesh>
  readonly lit: LitProgram
  readonly shadow: ShadowMap | null
  readonly ink: {
    readonly program: WebGLProgram
    readonly viewProjection: Location
    readonly model: Location
    readonly scale: Location
    readonly viewport: Location
    readonly width: Location
  }
  readonly sky: {
    readonly corners: WebGLBuffer
    readonly bands: SkyProgram
    readonly dots: SkyProgram
    readonly cloud: SkyProgram & {readonly cloud: Location}
  }
  readonly specks: {
    readonly program: WebGLProgram
    readonly buffer: WebGLBuffer
    readonly viewProjection: Location
    readonly right: Location
    readonly up: Location
  }
}

const upload = (gl: WebGLRenderingContext, bin: Bin, mesh: MeshData): GpuMesh => ({
  positions: bin.buffer(gl.ARRAY_BUFFER, mesh.positions),
  normals: bin.buffer(gl.ARRAY_BUFFER, mesh.normals),
  smooth: bin.buffer(gl.ARRAY_BUFFER, mesh.smooth),
  indices: bin.buffer(gl.ELEMENT_ARRAY_BUFFER, mesh.indices),
  count: mesh.indices.length,
})

const linkLit = (gl: WebGLRenderingContext, bin: Bin, flags: readonly string[]): LitProgram => {
  const program = bin.program(defines(flags) + LIT_VERTEX, defines(flags) + LIT_FRAGMENT, MESH_ATTRIBUTES)
  const at = (name: string): Location => gl.getUniformLocation(program, name)
  return {
    program,
    viewProjection: at("uViewProjection"),
    model: at("uModel"),
    scale: at("uScale"),
    lightMatrix: at("uLightMatrix"),
    color: at("uColor"),
    color2: at("uColor2"),
    color3: at("uColor3"),
    pattern: at("uPattern"),
    rim: at("uRim"),
    light: at("uLight"),
    eye: at("uEye"),
    ball: at("uBall"),
    shadowMap: at("uShadowMap"),
    shadowInfo: at("uShadowInfo"),
  }
}

const complete = (gl: WebGLRenderingContext): boolean =>
  gl.checkFramebufferStatus(gl.FRAMEBUFFER) === gl.FRAMEBUFFER_COMPLETE

const shadowTexture = (gl: WebGLRenderingContext, texture: WebGLTexture): void => {
  gl.bindTexture(gl.TEXTURE_2D, texture)
  // nearest: depths must not be blended with each other, only compared
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
}

// The framebuffer and texture of a shadow map, or null where this kind
// cannot be had. Whatever it made is left in the bin for the caller to drop.
const shadowTarget = (
  gl: WebGLRenderingContext,
  bin: Bin,
  size: number,
  packed: boolean,
): {readonly framebuffer: WebGLFramebuffer; readonly texture: WebGLTexture} | null => {
  const framebuffer = bin.framebuffer()
  const texture = bin.texture()
  shadowTexture(gl, texture)
  gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer)

  if (packed) {
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, size, size, 0, gl.RGBA, gl.UNSIGNED_BYTE, null)
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture, 0)
    const depth = bin.renderbuffer()
    gl.bindRenderbuffer(gl.RENDERBUFFER, depth)
    gl.renderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT16, size, size)
    gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, depth)
    return complete(gl) ? {framebuffer, texture} : null
  }

  gl.texImage2D(gl.TEXTURE_2D, 0, gl.DEPTH_COMPONENT, size, size, 0, gl.DEPTH_COMPONENT, gl.UNSIGNED_INT, null)
  gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.TEXTURE_2D, texture, 0)
  if (complete(gl)) return {framebuffer, texture}
  // Some drivers will not take a framebuffer with no colour at all.
  const color = bin.renderbuffer()
  gl.bindRenderbuffer(gl.RENDERBUFFER, color)
  gl.renderbufferStorage(gl.RENDERBUFFER, gl.RGBA4, size, size)
  gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.RENDERBUFFER, color)
  return complete(gl) ? {framebuffer, texture} : null
}

// Tries a depth texture, then depth packed into colour, then nothing. Each
// attempt builds its target and both programs that use it; any failure drops
// that attempt whole and moves on to the next.
const buildShadows = (
  gl: WebGLRenderingContext,
  bin: Bin,
  derivatives: boolean,
): {readonly lit: LitProgram; readonly shadow: ShadowMap | null} => {
  const extra = derivatives ? ["DERIVATIVES"] : []
  const precision = gl.getShaderPrecisionFormat(gl.FRAGMENT_SHADER, gl.HIGH_FLOAT)
  const highp = precision !== null && precision.precision > 0
  const depthTexture = gl.getExtension("WEBGL_depth_texture") !== null
  const limit = Math.min(
    Number(gl.getParameter(gl.MAX_TEXTURE_SIZE)),
    Number(gl.getParameter(gl.MAX_RENDERBUFFER_SIZE)),
  )
  const size = Math.min(SHADOW_SIZE, Number.isFinite(limit) && limit > 0 ? limit : 0)

  const kinds: readonly boolean[] = [...(depthTexture ? [false] : []), ...(highp ? [true] : [])]
  for (const packed of size >= 256 ? kinds : []) {
    const attempt = createBin(gl)
    try {
      const target = shadowTarget(gl, attempt, size, packed)
      if (target) {
        const program = attempt.program(
          CASTER_VERTEX,
          packed ? CASTER_PACKED_FRAGMENT : CASTER_DEPTH_FRAGMENT,
          MESH_ATTRIBUTES,
        )
        const lit = linkLit(gl, attempt, [...extra, "SHADOWS", ...(packed ? ["PACKED"] : [])])
        gl.bindFramebuffer(gl.FRAMEBUFFER, null)
        // Everything worked: hand ownership to the main bin.
        bin.adopt(attempt)
        return {
          lit,
          shadow: {
            ...target,
            size,
            depthScale: 1 / (2 * SHADOW_STANDOFF),
            packed,
            program,
            lightMatrix: gl.getUniformLocation(program, "uLightMatrix"),
            model: gl.getUniformLocation(program, "uModel"),
            scale: gl.getUniformLocation(program, "uScale"),
          },
        }
      }
    } catch (error) {
      console.warn("shadow map unavailable:", error)
    }
    gl.bindFramebuffer(gl.FRAMEBUFFER, null)
    attempt.release()
  }

  gl.bindFramebuffer(gl.FRAMEBUFFER, null)
  return {lit: linkLit(gl, bin, extra), shadow: null}
}

// Every mesh the scene may ask for. The record type makes the checker insist
// a new MeshName is listed here too.
const MESH_NAME_SET: Readonly<Record<MeshName, true>> = {box: true, sphere: true, torus: true, gem: true, cylinder: true, disc: true}
const MESH_NAMES: readonly MeshName[] = Object.keys(MESH_NAME_SET).filter((name): name is MeshName => name in MESH_NAME_SET)

const fract = (x: number): number => x - Math.floor(x)
// x mod span, always 0..span, as GLSL's mod is
const wrap = (x: number, span: number): number => x - span * Math.floor(x / span)

const createGpu = (gl: WebGLRenderingContext, meshes: Meshes): Gpu => {
  const bin = createBin(gl)
  try {
    // Asked for on every build, because a restored context has none enabled.
    const derivatives = gl.getExtension("OES_standard_derivatives") !== null

    // Walked by name rather than with Object.entries, so the keys stay MeshName.
    const table = new Map<MeshName, GpuMesh>()
    for (const name of MESH_NAMES) table.set(name, upload(gl, bin, meshes[name]))

    let shaded: {readonly lit: LitProgram; readonly shadow: ShadowMap | null}
    try {
      shaded = buildShadows(gl, bin, derivatives)
    } catch (error) {
      // A driver that advertises derivatives but will not compile them.
      if (!derivatives) throw error
      shaded = buildShadows(gl, bin, false)
    }

    const ink = bin.program(INK_VERTEX, INK_FRAGMENT, MESH_ATTRIBUTES)
    const skyPart = (flag: string): SkyProgram => {
      const program = bin.program(SKY_VERTEX, defines([flag]) + SKY_FRAGMENT, ["aCorner"])
      return {
        program,
        rect: gl.getUniformLocation(program, "uRect"),
        top: gl.getUniformLocation(program, "uTop"),
        bottom: gl.getUniformLocation(program, "uBottom"),
        screen: gl.getUniformLocation(program, "uScreen"),
      }
    }
    const bands = skyPart("BANDS")
    const dots = skyPart("DOTS")
    const cloud = skyPart("CLOUD")
    let specks: WebGLProgram
    try {
      specks = bin.program(SPECK_VERTEX, defines(derivatives ? ["DERIVATIVES"] : []) + SPECK_FRAGMENT, SPECK_ATTRIBUTES)
    } catch (error) {
      if (!derivatives) throw error
      specks = bin.program(SPECK_VERTEX, SPECK_FRAGMENT, SPECK_ATTRIBUTES)
    }
    const at = (program: WebGLProgram, name: string): Location => gl.getUniformLocation(program, name)

    return {
      bin,
      meshes: table,
      lit: shaded.lit,
      shadow: shaded.shadow,
      ink: {
        program: ink,
        viewProjection: at(ink, "uViewProjection"),
        model: at(ink, "uModel"),
        scale: at(ink, "uScale"),
        viewport: at(ink, "uViewport"),
        width: at(ink, "uWidth"),
      },
      sky: {
        corners: bin.buffer(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1])),
        bands,
        dots,
        cloud: {...cloud, cloud: at(cloud.program, "uCloud")},
      },
      specks: {
        program: specks,
        buffer: bin.buffer(gl.ARRAY_BUFFER, null),
        viewProjection: at(specks, "uViewProjection"),
        right: at(specks, "uRight"),
        up: at(specks, "uUp"),
      },
    }
  } catch (error) {
    bin.release()
    throw error
  }
}

// --- the light's view ------------------------------------------------------

const normalized = (v: Vec3): Vec3 => {
  const length = Math.hypot(v[0], v[1], v[2])
  return length > 1e-9 ? [v[0] / length, v[1] / length, v[2] / length] : [0, 1, 0]
}
const dot3 = (a: Vec3, b: Vec3): number => a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
const cross3 = (a: Vec3, b: Vec3): Vec3 => [
  a[1] * b[2] - a[2] * b[1],
  a[2] * b[0] - a[0] * b[2],
  a[0] * b[1] - a[1] * b[0],
]

// An orthographic view down the light onto a square box round `center`,
// written into `out`. The box's centre is snapped to whole texels across the
// light, so as the ball rolls the map moves in texel steps and each shadow
// edge lands on the same texels frame after frame instead of shimmering.
const writeLightMatrix = (out: Float32Array, light: Vec3, center: Vec3, size: number): void => {
  const l = normalized(light)
  const right = normalized(Math.abs(l[1]) > 0.99 ? cross3([0, 0, 1], l) : cross3([0, 1, 0], l))
  const up = cross3(l, right)
  const texel = (2 * SHADOW_HALF) / size
  const snap = (x: number): number => Math.round(x / texel) * texel
  const cr = snap(dot3(center, right))
  const cu = snap(dot3(center, up))
  const cl = snap(dot3(center, l))
  const h = SHADOW_HALF
  const d = SHADOW_STANDOFF

  // column-major; depth runs from 0 at the light's eye to 2d beyond it
  out[0] = right[0] / h
  out[1] = up[0] / h
  out[2] = -l[0] / d
  out[3] = 0
  out[4] = right[1] / h
  out[5] = up[1] / h
  out[6] = -l[1] / d
  out[7] = 0
  out[8] = right[2] / h
  out[9] = up[2] / h
  out[10] = -l[2] / d
  out[11] = 0
  out[12] = -cr / h
  out[13] = -cu / h
  out[14] = cl / d
  out[15] = 1
}

// --- the renderer ----------------------------------------------------------

// Returns null where WebGL is not to be had.
export const createRenderer = (canvas: HTMLCanvasElement, meshes: Meshes): Renderer | null => {
  try {
    return build(canvas, meshes)
  } catch (error) {
    console.error(error)
    return null
  }
}

const build = (canvas: HTMLCanvasElement, meshes: Meshes): Renderer | null => {
  const gl = canvas.getContext("webgl", {antialias: true, alpha: false, powerPreference: "high-performance"})
  if (!gl) return null

  let gpu: Gpu | null = createGpu(gl, meshes)
  let width = canvas.width
  let height = canvas.height
  let pixelRatio = 1
  // the sky's own clock, fed by how far the stage clock moved, so a restart
  // (which winds the stage clock back to 0) does not throw the clouds back
  let skyTime = 0
  let lastTime: number | null = null
  // the camera's heading, unwrapped, so clouds never jump when it passes ±π
  let pan = 0
  let lastYaw: number | null = null
  let reported = false
  let destroyed = false

  // Reused every frame, so drawing allocates nothing for matrices.
  const matrix = new Float32Array(16)
  const lightMatrix = new Float32Array(16)
  let specks = new Float32Array(64 * SPECK_VERTICES * SPECK_FLOATS)
  let specksCapacity = 0
  // how many attribute slots are switched on, counting up from 0
  let enabled = 0

  const onLost = (event: Event): void => {
    // Without this the browser will not offer the context back.
    event.preventDefault()
    gpu = null
    // a restored context starts with nothing enabled and no buffer storage
    specksCapacity = 0
    enabled = 0
  }
  const onRestored = (): void => {
    if (destroyed) return
    try {
      gpu = createGpu(gl, meshes)
    } catch (error) {
      console.error(error)
      gpu = null
    }
  }
  canvas.addEventListener("webglcontextlost", onLost)
  canvas.addEventListener("webglcontextrestored", onRestored)

  const setMatrix = (location: Location, m: Mat4): void => {
    matrix.set(m)
    gl.uniformMatrix4fv(location, false, matrix)
  }
  const setVec3 = (location: Location, v: Vec3): void => {
    gl.uniform3f(location, v[0], v[1], v[2])
  }

  // Exactly these attribute slots on, the rest off: a slot left on from
  // another program would read past the end of whatever buffer it last had.
  const slots = (count: number): void => {
    for (let i = count; i < enabled; i++) gl.disableVertexAttribArray(i)
    for (let i = enabled; i < count; i++) gl.enableVertexAttribArray(i)
    enabled = count
  }
  const attribute = (slot: number, b: WebGLBuffer): void => {
    gl.bindBuffer(gl.ARRAY_BUFFER, b)
    gl.vertexAttribPointer(slot, 3, gl.FLOAT, false, 0, 0)
  }

  const drawShadowMap = (g: Gpu, shadow: ShadowMap, scene: Scene): void => {
    const [bx, by, bz] = scene.ball.position
    const ahead = normalized([bx - scene.eye[0], 0, bz - scene.eye[2]])
    writeLightMatrix(lightMatrix, scene.light, [bx + ahead[0] * SHADOW_LEAD, by, bz + ahead[2] * SHADOW_LEAD], shadow.size)

    gl.bindFramebuffer(gl.FRAMEBUFFER, shadow.framebuffer)
    gl.viewport(0, 0, shadow.size, shadow.size)
    gl.clearColor(1, 1, 1, 1)
    gl.clearDepth(1)
    gl.colorMask(shadow.packed, shadow.packed, shadow.packed, shadow.packed)
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

    gl.useProgram(shadow.program)
    gl.enable(gl.DEPTH_TEST)
    gl.enable(gl.CULL_FACE)
    // Only the faces turned away from the light go in the map. A lit face
    // then never compares against itself, which is where acne comes from.
    gl.cullFace(gl.FRONT)
    gl.uniformMatrix4fv(shadow.lightMatrix, false, lightMatrix)
    slots(1)

    for (const item of scene.items) {
      if (!item.castsShadow) continue
      const mesh = g.meshes.get(item.mesh)
      if (!mesh) continue
      attribute(SLOT_POSITION, mesh.positions)
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, mesh.indices)
      setMatrix(shadow.model, item.model)
      setVec3(shadow.scale, item.scale)
      gl.drawElements(gl.TRIANGLES, mesh.count, gl.UNSIGNED_SHORT, 0)
    }

    gl.colorMask(true, true, true, true)
    gl.bindFramebuffer(gl.FRAMEBUFFER, null)
    gl.viewport(0, 0, width, height)
  }

  const drawSky = (g: Gpu, scene: Scene): void => {
    const since = lastTime === null ? 0 : scene.time - lastTime
    lastTime = scene.time
    skyTime += since > 0 && since < 0.5 ? since : 0

    const [ex, , ez] = scene.eye
    const [bx, , bz] = scene.ball.position
    const yaw = Math.atan2(bx - ex, bz - ez)
    if (lastYaw !== null) {
      let turn = yaw - lastYaw
      if (turn > Math.PI) turn -= 2 * Math.PI
      if (turn < -Math.PI) turn += 2 * Math.PI
      pan += turn
    }
    lastYaw = yaw

    // Where the level horizon in front of the camera lands on screen.
    const far = 1000
    const toward = normalized([bx - ex, 0, bz - ez])
    const [, hy] = mat4TransformPoint(scene.viewProjection, [ex + toward[0] * far, scene.eye[1], ez + toward[2] * far])
    const horizon = Number.isFinite(hy) ? Math.min(Math.max(hy * 0.5 + 0.5, 0), 0.95) : 0.5

    const aspect = width / Math.max(1, height)
    const part = (sky: SkyProgram, x0: number, y0: number, x1: number, y1: number): void => {
      gl.useProgram(sky.program)
      gl.uniform4f(sky.rect, x0, y0, x1, y1)
      setVec3(sky.top, scene.sky.top)
      setVec3(sky.bottom, scene.sky.bottom)
      gl.uniform3f(sky.screen, aspect, Math.max(1, height), pixelRatio)
    }

    gl.enable(gl.DEPTH_TEST)
    gl.depthFunc(gl.LEQUAL)
    gl.depthMask(false)
    gl.disable(gl.CULL_FACE)
    slots(1)
    gl.bindBuffer(gl.ARRAY_BUFFER, g.sky.corners)
    gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0)

    part(g.sky.bands, 0, 0, 1, 1)
    gl.drawArrays(gl.TRIANGLES, 0, 6)

    gl.enable(gl.BLEND)
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
    // the dots fade out by 30% of the way up the screen
    part(g.sky.dots, 0, 0, 1, 0.3)
    gl.drawArrays(gl.TRIANGLES, 0, 6)

    // Four clouds drifting right at their own pace, wrapping round, and
    // sliding against the camera as it turns so the sky seems far away. Held
    // upright the screen is narrow, so they shrink to keep a few in view.
    // Positions are in screen heights across and up.
    const span = aspect + 1.4
    const low = Math.min(horizon, 0.45)
    const shrink = Math.min(Math.max(aspect * 1.3, 0.55), 1)
    const margin = (4 * pixelRatio) / Math.max(1, height)
    for (let i = 0; i < 4; i++) {
      const size = (0.075 + 0.03 * fract(i * 0.37 + 0.2)) * shrink
      const x = wrap(i * 0.29 * span + skyTime * (0.008 + 0.004 * i) - pan * 0.3, span) - 0.7
      const y = low + 0.04 + (1 - low) * (0.1 + 0.7 * fract(i * 0.618 + 0.1))
      // the cloud and its shifted twin reach about this far from its anchor
      const x0 = (x - 1.15 * size - margin) / aspect
      const x1 = (x + 1.05 * size + margin) / aspect
      if (x1 < 0 || x0 > 1) continue
      part(g.sky.cloud, x0, y - 0.35 * size - margin, x1, y + 0.75 * size + margin)
      gl.uniform3f(g.sky.cloud.cloud, x, y, size)
      gl.drawArrays(gl.TRIANGLES, 0, 6)
    }

    gl.disable(gl.BLEND)
    gl.depthMask(true)
    gl.depthFunc(gl.LESS)
  }

  const drawLit = (g: Gpu, scene: Scene): void => {
    const lit = g.lit
    gl.useProgram(lit.program)
    gl.enable(gl.DEPTH_TEST)
    gl.enable(gl.CULL_FACE)
    gl.cullFace(gl.BACK)

    setMatrix(lit.viewProjection, scene.viewProjection)
    setVec3(lit.light, normalized(scene.light))
    setVec3(lit.eye, scene.eye)
    const [bx, by, bz] = scene.ball.position
    gl.uniform4f(lit.ball, bx, by, bz, scene.ball.radius)

    if (g.shadow) {
      const s = g.shadow
      gl.uniformMatrix4fv(lit.lightMatrix, false, lightMatrix)
      gl.activeTexture(gl.TEXTURE0)
      gl.bindTexture(gl.TEXTURE_2D, s.texture)
      gl.uniform1i(lit.shadowMap, 0)
      gl.uniform3f(lit.shadowInfo, s.size, SHADOW_BIAS * s.depthScale, SHADOW_SLOPE_BIAS * s.depthScale)
    }

    slots(2)
    for (const item of scene.items) {
      const mesh = g.meshes.get(item.mesh)
      if (!mesh) continue
      attribute(SLOT_POSITION, mesh.positions)
      attribute(SLOT_NORMAL, mesh.normals)
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, mesh.indices)
      setMatrix(lit.model, item.model)
      setVec3(lit.scale, item.scale)
      setVec3(lit.color, item.color)
      setVec3(lit.color2, item.color2)
      setVec3(lit.color3, item.color3)
      gl.uniform1f(lit.pattern, patternCode(item.pattern))
      gl.uniform1f(lit.rim, hasRim(item) ? 1 : 0)
      gl.drawElements(gl.TRIANGLES, mesh.count, gl.UNSIGNED_SHORT, 0)
    }
  }

  const drawInk = (g: Gpu, scene: Scene): void => {
    const ink = g.ink
    gl.useProgram(ink.program)
    // the inside of the swollen hull, so only its rim shows round the object
    gl.cullFace(gl.FRONT)
    setMatrix(ink.viewProjection, scene.viewProjection)
    gl.uniform2f(ink.viewport, Math.max(1, width), Math.max(1, height))

    const short = Math.max(1, Math.min(width, height))
    const lineWidth = (outline: number): number => {
      const fromScreen = outline * OUTLINE_SCREEN_FRACTION * short
      const lo = outline * OUTLINE_MIN_CSS * pixelRatio
      const hi = outline * OUTLINE_MAX_CSS * pixelRatio
      // never thinner than one device pixel, or it breaks up into dashes
      return Math.max(1, Math.min(Math.max(fromScreen, lo), hi))
    }

    slots(SLOT_SMOOTH + 1)
    // The normal slot is on but unused by this program; point it somewhere
    // valid all the same.
    for (const item of scene.items) {
      if (item.outline <= 0) continue
      const mesh = g.meshes.get(item.mesh)
      if (!mesh) continue
      attribute(SLOT_POSITION, mesh.positions)
      attribute(SLOT_NORMAL, mesh.normals)
      attribute(SLOT_SMOOTH, mesh.smooth)
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, mesh.indices)
      setMatrix(ink.model, item.model)
      setVec3(ink.scale, item.scale)
      gl.uniform1f(ink.width, lineWidth(item.outline))
      gl.drawElements(gl.TRIANGLES, mesh.count, gl.UNSIGNED_SHORT, 0)
    }
  }

  const drawSpecks = (g: Gpu, scene: Scene): void => {
    const count = scene.particles.length
    if (count === 0) return

    const needed = count * SPECK_VERTICES * SPECK_FLOATS
    if (specks.length < needed) {
      let length = specks.length
      while (length < needed) length *= 2
      specks = new Float32Array(length)
    }
    let o = 0
    for (const p of scene.particles) {
      for (const [cx, cy] of SPECK_CORNERS) {
        specks[o++] = p.position[0]
        specks[o++] = p.position[1]
        specks[o++] = p.position[2]
        specks[o++] = cx
        specks[o++] = cy
        specks[o++] = p.color[0]
        specks[o++] = p.color[1]
        specks[o++] = p.color[2]
        specks[o++] = Math.min(Math.max(p.alpha, 0), 1)
        specks[o++] = p.size
      }
    }

    gl.bindBuffer(gl.ARRAY_BUFFER, g.specks.buffer)
    if (specksCapacity < specks.length) {
      gl.bufferData(gl.ARRAY_BUFFER, specks.byteLength, gl.DYNAMIC_DRAW)
      specksCapacity = specks.length
    }
    gl.bufferSubData(gl.ARRAY_BUFFER, 0, specks.subarray(0, needed))

    // The camera's right and up, in the world the items are placed in, are
    // the first two rows of the view-projection, give or take a scale.
    const m = scene.viewProjection
    const right = normalized([m[0], m[4], m[8]])
    const up = normalized([m[1], m[5], m[9]])

    gl.useProgram(g.specks.program)
    gl.disable(gl.CULL_FACE)
    gl.enable(gl.BLEND)
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
    // tested against the world, but not written, so specks never hide each other
    gl.depthMask(false)
    setMatrix(g.specks.viewProjection, m)
    setVec3(g.specks.right, right)
    setVec3(g.specks.up, up)

    slots(SPECK_ATTRIBUTES.length)
    const stride = SPECK_FLOATS * 4
    gl.vertexAttribPointer(0, 3, gl.FLOAT, false, stride, 0)
    gl.vertexAttribPointer(1, 2, gl.FLOAT, false, stride, 12)
    gl.vertexAttribPointer(2, 4, gl.FLOAT, false, stride, 20)
    gl.vertexAttribPointer(3, 1, gl.FLOAT, false, stride, 36)
    gl.drawArrays(gl.TRIANGLES, 0, count * SPECK_VERTICES)

    gl.depthMask(true)
    gl.disable(gl.BLEND)
  }

  return {
    resize(w, h) {
      if (canvas.width !== w || canvas.height !== h) {
        canvas.width = w
        canvas.height = h
      }
      width = w
      height = h
      // Ink is sized in CSS pixels, so it needs to know how many device
      // pixels make one. Hidden canvases have no client size; assume 1.
      const ratio = canvas.clientWidth > 0 ? w / canvas.clientWidth : 1
      pixelRatio = Number.isFinite(ratio) ? Math.min(Math.max(ratio, 1), 3) : 1
      if (!gl.isContextLost()) gl.viewport(0, 0, w, h)
    },

    draw(scene) {
      const g = gpu
      if (!g || destroyed || gl.isContextLost()) return
      try {
        if (g.shadow) drawShadowMap(g, g.shadow, scene)
        gl.viewport(0, 0, width, height)
        gl.clear(gl.DEPTH_BUFFER_BIT)
        drawLit(g, scene)
        drawInk(g, scene)
        // last of the opaque passes, so it fills only what the stage left
        drawSky(g, scene)
        drawSpecks(g, scene)
      } catch (error) {
        // A bad frame is dropped, not thrown into the frame loop; once is
        // enough to say so.
        if (!reported) console.error(error)
        reported = true
      }
    },

    destroy() {
      if (destroyed) return
      destroyed = true
      canvas.removeEventListener("webglcontextlost", onLost)
      canvas.removeEventListener("webglcontextrestored", onRestored)
      if (gpu) gpu.bin.release()
      gpu = null
    },
  }
}

// The shiny things: the marble and the gems get a rim of light.
const hasRim = (item: SceneItem): boolean => item.pattern === "ball" || item.mesh === "gem"
