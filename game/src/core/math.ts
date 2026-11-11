// Vectors, quaternions and 4x4 matrices as plain arrays. Every function here
// returns a new value and touches nothing else: the whole core is built on
// that, so a game state can be compared, replayed and tested without a canvas.
//
// Conventions: y is up, the camera looks down -z at yaw 0, matrices are
// column-major (the layout WebGL expects), quaternions are [x, y, z, w].

import type {Axes, Mat4, Quat, Vec3} from "./types.ts"

export const UP: Vec3 = [0, 1, 0]
export const ZERO: Vec3 = [0, 0, 0]

export const add = (a: Vec3, b: Vec3): Vec3 => [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
export const sub = (a: Vec3, b: Vec3): Vec3 => [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
export const scale = (a: Vec3, s: number): Vec3 => [a[0] * s, a[1] * s, a[2] * s]
export const addScaled = (a: Vec3, b: Vec3, s: number): Vec3 => [a[0] + b[0] * s, a[1] + b[1] * s, a[2] + b[2] * s]
export const dot = (a: Vec3, b: Vec3): number => a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
export const cross = (a: Vec3, b: Vec3): Vec3 => [
  a[1] * b[2] - a[2] * b[1],
  a[2] * b[0] - a[0] * b[2],
  a[0] * b[1] - a[1] * b[0],
]
export const length = (a: Vec3): number => Math.hypot(a[0], a[1], a[2])
export const distance = (a: Vec3, b: Vec3): number => length(sub(a, b))
export const normalize = (a: Vec3): Vec3 => {
  const l = length(a)
  return l > 1e-9 ? scale(a, 1 / l) : ZERO
}
export const lerp = (a: Vec3, b: Vec3, t: number): Vec3 => [
  a[0] + (b[0] - a[0]) * t,
  a[1] + (b[1] - a[1]) * t,
  a[2] + (b[2] - a[2]) * t,
]
export const clamp = (x: number, lo: number, hi: number): number => Math.min(hi, Math.max(lo, x))

// The shortest signed turn from angle `from` to angle `to`, in (-pi, pi].
export const angleDelta = (from: number, to: number): number => {
  const d = (to - from) % (2 * Math.PI)
  if (d > Math.PI) return d - 2 * Math.PI
  if (d <= -Math.PI) return d + 2 * Math.PI
  return d
}

// --- randomness ------------------------------------------------------------

// mulberry32: a tiny, decent PRNG whose whole state is one 32-bit integer, so
// it can live in the game state and replay with it. Returns a value in [0, 1)
// and the seed to use next time.
export const random = (seed: number): readonly [number, number] => {
  const next = (seed + 0x6d2b79f5) | 0
  let t = Math.imul(next ^ (next >>> 15), 1 | next)
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
  return [((t ^ (t >>> 14)) >>> 0) / 4294967296, next]
}

// --- quaternions -----------------------------------------------------------

export const QUAT_IDENTITY: Quat = [0, 0, 0, 1]

export const quatMultiply = (a: Quat, b: Quat): Quat => [
  a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1],
  a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
  a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3],
  a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2],
]

export const quatNormalize = (q: Quat): Quat => {
  const l = Math.hypot(q[0], q[1], q[2], q[3])
  return l > 1e-9 ? [q[0] / l, q[1] / l, q[2] / l, q[3] / l] : QUAT_IDENTITY
}

// Advance an orientation by a world-space angular velocity for dt seconds.
export const quatIntegrate = (q: Quat, angularVelocity: Vec3, dt: number): Quat => {
  const w: Quat = [angularVelocity[0], angularVelocity[1], angularVelocity[2], 0]
  const dq = quatMultiply(w, q)
  const h = dt / 2
  return quatNormalize([q[0] + dq[0] * h, q[1] + dq[1] * h, q[2] + dq[2] * h, q[3] + dq[3] * h])
}

// The three basis vectors a quaternion rotates x, y and z onto.
export const quatToAxes = ([x, y, z, w]: Quat): Axes => [
  [1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w)],
  [2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w)],
  [2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y)],
]

// --- bases -----------------------------------------------------------------

export const AXES_IDENTITY: Axes = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]

// Rotation about the vertical. Yaw 0 leaves things alone; positive yaw turns
// counter-clockwise seen from above.
export const axesFromYaw = (yaw: number): Axes => {
  const c = Math.cos(yaw)
  const s = Math.sin(yaw)
  return [[c, 0, -s], [0, 1, 0], [s, 0, c]]
}

// World direction for "forward" (away from the camera) and "right" at a yaw.
export const forwardFromYaw = (yaw: number): Vec3 => [-Math.sin(yaw), 0, -Math.cos(yaw)]
export const rightFromYaw = (yaw: number): Vec3 => [Math.cos(yaw), 0, -Math.sin(yaw)]

// --- matrices --------------------------------------------------------------

export const mat4Identity = (): Mat4 => [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]

// Written out in full: a loop would index the tuples with plain numbers,
// which the checker cannot prove are in range.
export const mat4Multiply = (a: Mat4, b: Mat4): Mat4 => {
  const [a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15] = a
  const column = (x: number, y: number, z: number, w: number): readonly [number, number, number, number] => [
    a0 * x + a4 * y + a8 * z + a12 * w,
    a1 * x + a5 * y + a9 * z + a13 * w,
    a2 * x + a6 * y + a10 * z + a14 * w,
    a3 * x + a7 * y + a11 * z + a15 * w,
  ]
  return [
    ...column(b[0], b[1], b[2], b[3]),
    ...column(b[4], b[5], b[6], b[7]),
    ...column(b[8], b[9], b[10], b[11]),
    ...column(b[12], b[13], b[14], b[15]),
  ]
}

export const mat4Translation = ([x, y, z]: Vec3): Mat4 => [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, y, z, 1]

// A rigid transform: rotate onto `axes`, then move to `position`.
export const mat4FromBasis = (position: Vec3, axes: Axes): Mat4 => [
  axes[0][0], axes[0][1], axes[0][2], 0,
  axes[1][0], axes[1][1], axes[1][2], 0,
  axes[2][0], axes[2][1], axes[2][2], 0,
  position[0], position[1], position[2], 1,
]

export const mat4FromAxisAngle = (axis: Vec3, angle: number): Mat4 => {
  const [x, y, z] = normalize(axis)
  const c = Math.cos(angle)
  const s = Math.sin(angle)
  const t = 1 - c
  return [
    t * x * x + c, t * x * y + s * z, t * x * z - s * y, 0,
    t * x * y - s * z, t * y * y + c, t * y * z + s * x, 0,
    t * x * z + s * y, t * y * z - s * x, t * z * z + c, 0,
    0, 0, 0, 1,
  ]
}

export const mat4Perspective = (fovY: number, aspect: number, near: number, far: number): Mat4 => {
  const f = 1 / Math.tan(fovY / 2)
  const nf = 1 / (near - far)
  return [f / aspect, 0, 0, 0, 0, f, 0, 0, 0, 0, (far + near) * nf, -1, 0, 0, 2 * far * near * nf, 0]
}

export const mat4LookAt = (eye: Vec3, target: Vec3, up: Vec3 = UP): Mat4 => {
  const z = normalize(sub(eye, target))
  const x = normalize(cross(up, z))
  const y = cross(z, x)
  return [
    x[0], y[0], z[0], 0,
    x[1], y[1], z[1], 0,
    x[2], y[2], z[2], 0,
    -dot(x, eye), -dot(y, eye), -dot(z, eye), 1,
  ]
}

export const mat4TransformPoint = (m: Mat4, [x, y, z]: Vec3): Vec3 => {
  const w = m[3] * x + m[7] * y + m[11] * z + m[15]
  return [
    (m[0] * x + m[4] * y + m[8] * z + m[12]) / w,
    (m[1] * x + m[5] * y + m[9] * z + m[13]) / w,
    (m[2] * x + m[6] * y + m[10] * z + m[14]) / w,
  ]
}
