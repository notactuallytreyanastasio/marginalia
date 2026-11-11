// The physics engine: one rigid sphere against a world of oriented boxes,
// some of which move on rails.
//
// It is impulse based. Each step integrates gravity, then finds the deepest
// overlap, pushes the ball out along the contact normal and applies two
// impulses at the contact point: one along the normal (the bounce) and one
// across it (friction). Friction acts on the velocity of the ball's *surface*
// at the contact, which is what turns sliding into rolling and gives the
// 5/7·g·sin(θ) acceleration a solid sphere really has on a slope.
//
// Nothing here knows about tilt, levels, time limits or the screen. The tilt
// of the stage arrives as a gravity vector.

import {add, addScaled, clamp, cross, dot, length, quatIntegrate, scale, sub} from "./math.js"

export const BALL_RADIUS = 0.5

const RESTITUTION = 0.38
// Impacts slower than this do not bounce, or a resting ball would jitter.
const BOUNCE_THRESHOLD = 1.2
const FRICTION = 0.9
// Fraction of rolling speed lost per second to the surface.
const ROLLING_DRAG = 0.22
// The same, on a platform that is moving. Real friction alone passes only 2/7
// of a surface's acceleration to a ball resting on it — the tablecloth trick —
// which is honest and no fun: the platform leaves and the ball stays. Moving
// platforms are made tacky so that a ball left alone on one mostly rides it.
const MOVING_GRIP = 4
const MAX_SPEED = 45
const MAX_CONTACTS_PER_STEP = 4
// A solid sphere's moment of inertia is 2/5·m·r². An impulse J across the
// contact changes the surface velocity there by J·(1 + 5/2).
const SLIP_TO_IMPULSE = 2 / 7

// How long a moving platform lingers at each end of its travel: the sine that
// drives it is overdriven by this much and clipped, so the platform sits still
// in dock for a while instead of touching it for an instant.
const DWELL = 1.4

// Where a collider is, and how fast it is moving, at a moment in time. A
// moving platform is a pure function of the clock, so replaying a level
// replays its platforms exactly.
export const colliderAt = (collider, time) => {
  const motion = collider.motion
  if (!motion) return {center: collider.center, velocity: [0, 0, 0]}

  const omega = (2 * Math.PI) / motion.period
  const angle = omega * time + (motion.phase || 0)
  const u = clamp(DWELL * Math.sin(angle), -1, 1)
  // u·(3 − u²)/2 runs from -1 to 1 and is flat at both ends, so the platform
  // eases into and out of its stops rather than jolting.
  const offset = (u * (3 - u * u)) / 2
  const rate = Math.abs(u) < 1 ? 1.5 * (1 - u * u) * DWELL * Math.cos(angle) * omega : 0

  return {
    center: addScaled(collider.center, motion.amplitude, offset),
    velocity: scale(motion.amplitude, rate),
  }
}

// How a sphere at `position` overlaps a box, or null if it does not.
// Returns the world-space normal pointing out of the box and the depth.
export const sphereBoxContact = (position, radius, center, half, axes) => {
  const rel = sub(position, center)
  const local = [dot(rel, axes[0]), dot(rel, axes[1]), dot(rel, axes[2])]
  const closest = [
    clamp(local[0], -half[0], half[0]),
    clamp(local[1], -half[1], half[1]),
    clamp(local[2], -half[2], half[2]),
  ]
  const diff = sub(local, closest)
  const dist = length(diff)

  if (dist >= radius) return null

  let localNormal
  let depth

  if (dist > 1e-6) {
    localNormal = scale(diff, 1 / dist)
    depth = radius - dist
  } else {
    // The centre is inside the box: leave through the nearest face.
    let axis = 0
    let nearest = Infinity
    for (let i = 0; i < 3; i++) {
      const toFace = half[i] - Math.abs(local[i])
      if (toFace < nearest) {
        nearest = toFace
        axis = i
      }
    }
    localNormal = [0, 0, 0]
    localNormal[axis] = local[axis] >= 0 ? 1 : -1
    depth = radius + nearest
  }

  const normal = add(
    add(scale(axes[0], localNormal[0]), scale(axes[1], localNormal[1])),
    scale(axes[2], localNormal[2]),
  )

  return {normal, depth}
}

const deepestContact = (position, radius, placed) => {
  let best = null
  for (const item of placed) {
    const contact = sphereBoxContact(position, radius, item.center, item.collider.half, item.collider.axes)
    if (contact && (!best || contact.depth > best.depth)) {
      best = {...contact, velocity: item.velocity}
    }
  }
  return best
}

// Advance the ball by dt seconds.
//
//   ball      {position, velocity, angularVelocity, orientation}
//   colliders [{center, half, axes, motion?}]
//   time      the clock at the *end* of this step, for moving platforms
//   gravity   acceleration vector
//
// Returns {ball, grounded, impact} where impact is the hardest hit taken
// this step, in units of speed, for the shell to turn into sound.
export const stepBall = (ball, colliders, time, gravity, dt, radius = BALL_RADIUS) => {
  let velocity = addScaled(ball.velocity, gravity, dt)
  const speed = length(velocity)
  if (speed > MAX_SPEED) velocity = scale(velocity, MAX_SPEED / speed)

  let position = addScaled(ball.position, velocity, dt)
  let angularVelocity = ball.angularVelocity
  let grounded = false
  let impact = 0
  let surfaceVelocity = [0, 0, 0]

  const placed = colliders.map(collider => ({collider, ...colliderAt(collider, time)}))

  // Resolving the deepest overlap first matters where two boxes meet flush:
  // the face the ball is sitting on is handled, and the neighbour's edge then
  // no longer overlaps, so seams between platforms do not kick the ball.
  for (let i = 0; i < MAX_CONTACTS_PER_STEP; i++) {
    const contact = deepestContact(position, radius, placed)
    if (!contact) break

    const n = contact.normal
    position = addScaled(position, n, contact.depth)

    const relative = sub(velocity, contact.velocity)
    const approach = dot(relative, n)

    if (approach < 0) {
      const bounce = -approach > BOUNCE_THRESHOLD ? RESTITUTION : 0
      const normalImpulse = -(1 + bounce) * approach
      velocity = addScaled(velocity, n, normalImpulse)
      impact = Math.max(impact, -approach)

      // Velocity of the ball's surface where it touches the box.
      const arm = scale(n, -radius)
      const surface = add(sub(velocity, contact.velocity), cross(angularVelocity, arm))
      const slip = addScaled(surface, n, -dot(surface, n))
      const slipSpeed = length(slip)

      if (slipSpeed > 1e-6) {
        const wanted = slipSpeed * SLIP_TO_IMPULSE
        const allowed = FRICTION * normalImpulse
        const impulse = scale(slip, -Math.min(wanted, allowed) / slipSpeed)
        velocity = add(velocity, impulse)
        angularVelocity = add(angularVelocity, scale(cross(arm, impulse), 1 / (0.4 * radius * radius)))
      }
    }

    if (n[1] > 0.5) {
      grounded = true
      surfaceVelocity = contact.velocity
    }
  }

  if (grounded) {
    // Drag is measured against whatever the ball is standing on, so a ball
    // at rest on a moving platform stays at rest on it.
    const moving = length(surfaceVelocity) > 1e-6
    const keep = Math.exp(-(moving ? MOVING_GRIP : ROLLING_DRAG) * dt)
    velocity = add(surfaceVelocity, scale(sub(velocity, surfaceVelocity), keep))
    angularVelocity = scale(angularVelocity, Math.exp(-ROLLING_DRAG * dt))
  }

  return {
    ball: {
      position,
      velocity,
      angularVelocity,
      orientation: quatIntegrate(ball.orientation, angularVelocity, dt),
    },
    grounded,
    impact,
  }
}
