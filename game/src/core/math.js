// Vectors, quaternions and 4x4 matrices as plain arrays. Every function here
// returns a new value and touches nothing else: the whole core is built on
// that, so a game state can be compared, replayed and tested without a canvas.
//
// Conventions: y is up, the camera looks down -z at yaw 0, matrices are
// column-major (the layout WebGL expects), quaternions are [x, y, z, w].

export const UP = [0, 1, 0]

export const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
export const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
export const scale = (a, s) => [a[0] * s, a[1] * s, a[2] * s]
export const addScaled = (a, b, s) => [a[0] + b[0] * s, a[1] + b[1] * s, a[2] + b[2] * s]
export const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
export const cross = (a, b) => [
  a[1] * b[2] - a[2] * b[1],
  a[2] * b[0] - a[0] * b[2],
  a[0] * b[1] - a[1] * b[0],
]
export const length = a => Math.hypot(a[0], a[1], a[2])
export const distance = (a, b) => length(sub(a, b))
export const normalize = a => {
  const l = length(a)
  return l > 1e-9 ? scale(a, 1 / l) : [0, 0, 0]
}
export const lerp = (a, b, t) => [
  a[0] + (b[0] - a[0]) * t,
  a[1] + (b[1] - a[1]) * t,
  a[2] + (b[2] - a[2]) * t,
]
export const clamp = (x, lo, hi) => Math.min(hi, Math.max(lo, x))

// The shortest signed turn from angle `from` to angle `to`, in (-pi, pi].
export const angleDelta = (from, to) => {
  const d = (to - from) % (2 * Math.PI)
  if (d > Math.PI) return d - 2 * Math.PI
  if (d <= -Math.PI) return d + 2 * Math.PI
  return d
}

// --- quaternions -----------------------------------------------------------

export const QUAT_IDENTITY = [0, 0, 0, 1]

export const quatMultiply = (a, b) => [
  a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1],
  a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
  a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3],
  a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2],
]

export const quatNormalize = q => {
  const l = Math.hypot(q[0], q[1], q[2], q[3])
  return l > 1e-9 ? [q[0] / l, q[1] / l, q[2] / l, q[3] / l] : QUAT_IDENTITY
}

// Advance an orientation by a world-space angular velocity for dt seconds.
export const quatIntegrate = (q, angularVelocity, dt) => {
  const w = [angularVelocity[0], angularVelocity[1], angularVelocity[2], 0]
  const dq = quatMultiply(w, q)
  const h = dt / 2
  return quatNormalize([q[0] + dq[0] * h, q[1] + dq[1] * h, q[2] + dq[2] * h, q[3] + dq[3] * h])
}

// The three basis vectors a quaternion rotates x, y and z onto.
export const quatToAxes = ([x, y, z, w]) => [
  [1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w)],
  [2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w)],
  [2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y)],
]

// --- bases -----------------------------------------------------------------

export const AXES_IDENTITY = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]

// Rotation about the vertical. Yaw 0 leaves things alone; positive yaw turns
// counter-clockwise seen from above.
export const axesFromYaw = yaw => {
  const c = Math.cos(yaw)
  const s = Math.sin(yaw)
  return [[c, 0, -s], [0, 1, 0], [s, 0, c]]
}

// World direction for "forward" (away from the camera) and "right" at a yaw.
export const forwardFromYaw = yaw => [-Math.sin(yaw), 0, -Math.cos(yaw)]
export const rightFromYaw = yaw => [Math.cos(yaw), 0, -Math.sin(yaw)]

// --- matrices --------------------------------------------------------------

export const mat4Identity = () => [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]

export const mat4Multiply = (a, b) => {
  const out = new Array(16)
  for (let col = 0; col < 4; col++) {
    for (let row = 0; row < 4; row++) {
      out[col * 4 + row] =
        a[row] * b[col * 4] +
        a[4 + row] * b[col * 4 + 1] +
        a[8 + row] * b[col * 4 + 2] +
        a[12 + row] * b[col * 4 + 3]
    }
  }
  return out
}

export const mat4Translation = ([x, y, z]) => [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, y, z, 1]

// A rigid transform: rotate onto `axes`, then move to `position`.
export const mat4FromBasis = (position, axes) => [
  axes[0][0], axes[0][1], axes[0][2], 0,
  axes[1][0], axes[1][1], axes[1][2], 0,
  axes[2][0], axes[2][1], axes[2][2], 0,
  position[0], position[1], position[2], 1,
]

export const mat4FromAxisAngle = (axis, angle) => {
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

export const mat4Perspective = (fovY, aspect, near, far) => {
  const f = 1 / Math.tan(fovY / 2)
  const nf = 1 / (near - far)
  return [f / aspect, 0, 0, 0, 0, f, 0, 0, 0, 0, (far + near) * nf, -1, 0, 0, 2 * far * near * nf, 0]
}

export const mat4LookAt = (eye, target, up = UP) => {
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

export const mat4TransformPoint = (m, [x, y, z]) => {
  const w = m[3] * x + m[7] * y + m[11] * z + m[15]
  return [
    (m[0] * x + m[4] * y + m[8] * z + m[12]) / w,
    (m[1] * x + m[5] * y + m[9] * z + m[13]) / w,
    (m[2] * x + m[6] * y + m[10] * z + m[14]) / w,
  ]
}
