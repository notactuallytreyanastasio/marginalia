// The cel-shading engine. WebGL 1, no libraries, so it runs on any phone that
// can run the page at all.
//
// A frame is three passes over the scene the core describes:
//
//   1. sky     a banded gradient behind everything
//   2. toon    each object lit in three flat steps instead of a smooth falloff,
//              with a hard-edged highlight and a hard-edged drop shadow under
//              the ball
//   3. ink     each object again, turned inside out and swollen along its
//              smooth normals, in near-black. Only the rim that pokes out past
//              the lit object survives the depth test, and that rim is the
//              outline. Its width is scaled by depth so it stays the same
//              number of pixels near and far.

const VERTEX = `
attribute vec3 aPosition;
attribute vec3 aNormal;
attribute vec3 aSmooth;

uniform mat4 uViewProjection;
uniform mat4 uModel;
uniform vec3 uScale;
// shared with the fragment shader, so the two must agree on its precision
uniform mediump float uOutline;

varying vec3 vWorld;
varying vec3 vNormal;
varying vec3 vLocal;

void main() {
  mat3 rotation = mat3(uModel);
  vec4 world = uModel * vec4(aPosition * uScale, 1.0);

  if (uOutline > 0.0) {
    float depth = (uViewProjection * world).w;
    world.xyz += normalize(rotation * aSmooth) * uOutline * depth;
  }

  vWorld = world.xyz;
  vNormal = rotation * (aNormal / uScale);
  vLocal = aPosition;
  gl_Position = uViewProjection * world;
}
`

const FRAGMENT = `
precision mediump float;

uniform vec3 uColor;
uniform vec3 uColor2;
uniform vec3 uColor3;
uniform float uPattern;
uniform float uOutline;
uniform vec3 uLight;
uniform vec3 uEye;
uniform vec4 uBall;

varying vec3 vWorld;
varying vec3 vNormal;
varying vec3 vLocal;

const vec3 INK = vec3(0.11, 0.09, 0.13);

float gridLine(float coordinate, float spacing, float width) {
  float d = abs(fract(coordinate / spacing + 0.5) - 0.5) * spacing;
  return 1.0 - smoothstep(width, width * 2.2, d);
}

void main() {
  if (uOutline > 0.0) {
    gl_FragColor = vec4(INK, 1.0);
    return;
  }

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
  float shade = lit > 0.45 ? 1.0 : (lit > -0.05 ? 0.8 : 0.58);

  // the ball's shadow, straight down onto whatever is below it
  vec3 below = vWorld - uBall.xyz;
  if (uPattern < 1.5 && n.y > 0.3 && below.y < -0.2 && below.y > -14.0) {
    float radius = uBall.w * (1.0 + below.y * 0.035);
    if (length(below.xz) < radius) shade = min(shade, 0.58);
  }

  vec3 color = base * shade;

  if (gloss > 0.0) {
    vec3 toEye = normalize(uEye - vWorld);
    float highlight = dot(n, normalize(uLight + toEye));
    color = mix(color, vec3(1.0), step(0.965, highlight) * 0.85);
  }

  gl_FragColor = vec4(color, 1.0);
}
`

const SKY_VERTEX = `
attribute vec2 aCorner;
varying vec2 vUv;
void main() {
  vUv = aCorner * 0.5 + 0.5;
  gl_Position = vec4(aCorner, 0.0, 1.0);
}
`

const SKY_FRAGMENT = `
precision mediump float;
uniform vec3 uTop;
uniform vec3 uBottom;
varying vec2 vUv;
void main() {
  float bands = 7.0;
  float t = floor(vUv.y * bands) / (bands - 1.0);
  gl_FragColor = vec4(mix(uBottom, uTop, clamp(t, 0.0, 1.0)), 1.0);
}
`

const compile = (gl, type, source) => {
  const shader = gl.createShader(type)
  gl.shaderSource(shader, source)
  gl.compileShader(shader)
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    throw new Error(`shader: ${gl.getShaderInfoLog(shader)}`)
  }
  return shader
}

const link = (gl, vertex, fragment, attributes, uniforms) => {
  const program = gl.createProgram()
  gl.attachShader(program, compile(gl, gl.VERTEX_SHADER, vertex))
  gl.attachShader(program, compile(gl, gl.FRAGMENT_SHADER, fragment))
  // fixed slots, so one set of buffers serves every draw
  attributes.forEach((name, i) => gl.bindAttribLocation(program, i, name))
  gl.linkProgram(program)
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    throw new Error(`program: ${gl.getProgramInfoLog(program)}`)
  }
  const locations = {}
  uniforms.forEach(name => (locations[name] = gl.getUniformLocation(program, name)))
  return {program, uniforms: locations}
}

const upload = (gl, mesh) => {
  const buffer = (target, data) => {
    const b = gl.createBuffer()
    gl.bindBuffer(target, b)
    gl.bufferData(target, data, gl.STATIC_DRAW)
    return b
  }
  return {
    positions: buffer(gl.ARRAY_BUFFER, mesh.positions),
    normals: buffer(gl.ARRAY_BUFFER, mesh.normals),
    smooth: buffer(gl.ARRAY_BUFFER, mesh.smooth),
    indices: buffer(gl.ELEMENT_ARRAY_BUFFER, mesh.indices),
    count: mesh.indices.length,
  }
}

// Returns null where WebGL is not to be had.
export const createRenderer = (canvas, meshes) => {
  try {
    return build(canvas, meshes)
  } catch (error) {
    console.error(error)
    return null
  }
}

const build = (canvas, meshes) => {
  const gl = canvas.getContext("webgl", {antialias: true, alpha: false, powerPreference: "high-performance"})
  if (!gl) return null

  const toon = link(gl, VERTEX, FRAGMENT, ["aPosition", "aNormal", "aSmooth"], [
    "uViewProjection", "uModel", "uScale", "uOutline", "uColor", "uColor2", "uColor3",
    "uPattern", "uLight", "uEye", "uBall",
  ])
  const sky = link(gl, SKY_VERTEX, SKY_FRAGMENT, ["aCorner"], ["uTop", "uBottom"])

  const buffers = {}
  for (const [name, mesh] of Object.entries(meshes)) buffers[name] = upload(gl, mesh)

  const corners = gl.createBuffer()
  gl.bindBuffer(gl.ARRAY_BUFFER, corners)
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW)

  const bind = mesh => {
    const attribute = (index, buffer) => {
      gl.bindBuffer(gl.ARRAY_BUFFER, buffer)
      gl.enableVertexAttribArray(index)
      gl.vertexAttribPointer(index, 3, gl.FLOAT, false, 0, 0)
    }
    attribute(0, mesh.positions)
    attribute(1, mesh.normals)
    attribute(2, mesh.smooth)
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, mesh.indices)
  }

  const drawSky = colors => {
    gl.useProgram(sky.program)
    gl.disable(gl.DEPTH_TEST)
    gl.disable(gl.CULL_FACE)
    gl.disableVertexAttribArray(1)
    gl.disableVertexAttribArray(2)
    gl.bindBuffer(gl.ARRAY_BUFFER, corners)
    gl.enableVertexAttribArray(0)
    gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0)
    gl.uniform3fv(sky.uniforms.uTop, colors.top)
    gl.uniform3fv(sky.uniforms.uBottom, colors.bottom)
    gl.drawArrays(gl.TRIANGLES, 0, 3)
  }

  const drawItems = (items, outlines) => {
    const u = toon.uniforms
    gl.cullFace(outlines ? gl.FRONT : gl.BACK)

    for (const item of items) {
      if (outlines && !item.outline) continue
      const mesh = buffers[item.mesh]
      bind(mesh)
      gl.uniformMatrix4fv(u.uModel, false, item.model)
      gl.uniform3fv(u.uScale, item.scale)
      gl.uniform1f(u.uOutline, outlines ? item.outline : 0)
      if (!outlines) {
        gl.uniform3fv(u.uColor, item.color)
        gl.uniform3fv(u.uColor2, item.color2 || item.color)
        gl.uniform3fv(u.uColor3, item.color3 || item.color)
        gl.uniform1f(u.uPattern, item.pattern)
      }
      gl.drawElements(gl.TRIANGLES, mesh.count, gl.UNSIGNED_SHORT, 0)
    }
  }

  return {
    resize(width, height) {
      if (canvas.width !== width || canvas.height !== height) {
        canvas.width = width
        canvas.height = height
      }
      gl.viewport(0, 0, width, height)
    },

    draw(scene) {
      gl.clear(gl.DEPTH_BUFFER_BIT)
      drawSky(scene.sky)

      gl.useProgram(toon.program)
      gl.enable(gl.DEPTH_TEST)
      gl.enable(gl.CULL_FACE)

      const u = toon.uniforms
      gl.uniformMatrix4fv(u.uViewProjection, false, scene.viewProjection)
      gl.uniform3fv(u.uLight, scene.light)
      gl.uniform3fv(u.uEye, scene.eye)
      gl.uniform4f(u.uBall, ...scene.ball.position, scene.ball.radius)

      drawItems(scene.items, false)
      drawItems(scene.items, true)
    },
  }
}
