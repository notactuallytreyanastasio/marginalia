// The physics engine: one rigid sphere against a world of oriented boxes,
// some of which move on rails or turn in place, and a few round bumpers.
//
// It is impulse based. Each step integrates gravity, then finds the deepest
// overlap, pushes the ball out along the contact normal and applies two
// impulses at the contact point: one along the normal (the bounce) and one
// across it (friction). Friction acts on the velocity of the ball's *surface*
// at the contact, which is what turns sliding into rolling and gives the
// 5/7·g·sin(θ) acceleration a solid sphere really has on a slope.
//
// A step never moves the ball further than a fraction of its radius: a long
// or fast step is cut into as many short ones as that takes, so the ball
// cannot pass through a thin floor or wall between two looks at the world.
//
// Nothing here knows about tilt, levels, time limits or the screen. The tilt
// of the stage arrives as a gravity vector.

import {UP, ZERO, add, addScaled, clamp, cross, dot, length, quatIntegrate, scale, sub} from "./math.ts"
import type {Axes, Ball, Collider, Mover, Vec3} from "./types.ts"

export const BALL_RADIUS = 0.5

const RESTITUTION = 0.38
// Impacts slower than this do not bounce, or a resting ball would jitter.
const BOUNCE_THRESHOLD = 1.2
const FRICTION = 0.9
// Fraction of rolling speed lost per second to the surface.
const ROLLING_DRAG = 0.22
// Real friction alone passes only 2/7 of a surface's acceleration to a ball
// resting on it — the tablecloth trick — which is honest and no fun: the
// platform leaves and the ball stays. So a ball standing on something that
// moves is given all of the surface's acceleration where it stands (for a
// turntable that includes the pull toward the hub that keeps it going round),
// and on top of that is drawn toward the surface's speed at this rate, so one
// stepped onto a moving platform soon goes with it. Not so hard that rolling
// across a moving platform feels like wading.
const MOVING_GRIP = 2.5
export const MAX_SPEED = 45
const MAX_CONTACTS_PER_STEP = 4
// The furthest the ball may travel in one look at the world. Half a radius
// means that, coming straight at the thinnest floor (0.6), the centre is
// first seen at least a quarter of the radius outside it, never past its
// middle, so it is always pushed back out the side it came in.
const MAX_TRAVEL = BALL_RADIUS / 2
// A runaway dt (a tab woken after an hour) is not worth thousands of steps.
const MAX_SPLITS = 256
// A solid sphere's moment of inertia is 2/5·m·r². An impulse J across the
// contact changes the surface velocity there by J·(1 + 5/2).
const SLIP_TO_IMPULSE = 2 / 7

// How long a moving platform lingers at each end of its travel: the sine that
// drives it is overdriven by this much and clipped, so the platform sits still
// in dock for a while instead of touching it for an instant.
const DWELL = 1.4

export interface Placement {
  readonly center: Vec3
  readonly velocity: Vec3
  readonly axes: Axes
  // about the centre, world space
  readonly angularVelocity: Vec3
}

export interface Contact {
  // out of the box, world space
  readonly normal: Vec3
  readonly depth: number
}

export interface BallStep {
  readonly ball: Ball
  readonly grounded: boolean
  // the hardest hit taken this step, in units of speed
  readonly impact: number
  // indices into the colliders of the bumpers that kicked, each listed once
  readonly bumped: readonly number[]
}

// Turn a vector about the vertical by `angle`, the same way axesFromYaw does.
const yawVector = (v: Vec3, angle: number): Vec3 => {
  const c = Math.cos(angle)
  const s = Math.sin(angle)
  return [c * v[0] + s * v[2], v[1], c * v[2] - s * v[0]]
}

const sliding = (collider: Mover, time: number): Placement => {
  const motion = collider.motion
  const omega = (2 * Math.PI) / motion.period
  const angle = omega * time + motion.phase
  const u = clamp(DWELL * Math.sin(angle), -1, 1)
  // u·(3 − u²)/2 runs from -1 to 1 and is flat at both ends, so the platform
  // eases into and out of its stops rather than jolting.
  const offset = (u * (3 - u * u)) / 2
  const rate = Math.abs(u) < 1 ? 1.5 * (1 - u * u) * DWELL * Math.cos(angle) * omega : 0

  return {
    center: addScaled(collider.center, motion.amplitude, offset),
    velocity: scale(motion.amplitude, rate),
    axes: collider.axes,
    angularVelocity: ZERO,
  }
}

// Where a collider is, which way it faces and how fast it is moving, at a
// moment in time. Moving and turning platforms are pure functions of the
// clock, so replaying a level replays its platforms exactly.
export const colliderAt = (collider: Collider, time: number): Placement => {
  switch (collider.kind) {
    case "floor":
    case "wall":
    case "bumper":
      return {center: collider.center, velocity: ZERO, axes: collider.axes, angularVelocity: ZERO}
    case "mover":
      return sliding(collider, time)
    case "rotor": {
      const angle = collider.spin.phase + collider.spin.rate * time
      const [x, y, z] = collider.axes
      return {
        center: collider.center,
        velocity: ZERO,
        axes: [yawVector(x, angle), yawVector(y, angle), yawVector(z, angle)],
        angularVelocity: [0, collider.spin.rate, 0],
      }
    }
    default: {
      const unreachable: never = collider
      return unreachable
    }
  }
}

// How fast the surface of a placed collider is moving at a point on it:
// the slide of the whole thing plus ω × r for its turn.
export const surfaceVelocityAt = (placement: Placement, point: Vec3): Vec3 =>
  add(placement.velocity, cross(placement.angularVelocity, sub(point, placement.center)))

// The face nearest a point inside a box: the local axis (0, 1, 2) and how far
// the point is from that face.
const nearestFace = (local: Vec3, half: Vec3): {readonly axis: 0 | 1 | 2; readonly distance: number} => {
  const x = half[0] - Math.abs(local[0])
  const y = half[1] - Math.abs(local[1])
  const z = half[2] - Math.abs(local[2])
  // ties go to the earlier axis, as a strict `<` scan would
  if (x <= y && x <= z) return {axis: 0, distance: x}
  if (y <= z) return {axis: 1, distance: y}
  return {axis: 2, distance: z}
}

// How a sphere at `position` overlaps a box, or null if it does not.
// Returns the world-space normal pointing out of the box and the depth.
export const sphereBoxContact = (
  position: Vec3,
  radius: number,
  center: Vec3,
  half: Vec3,
  axes: Axes,
): Contact | null => {
  const rel = sub(position, center)
  const local: Vec3 = [dot(rel, axes[0]), dot(rel, axes[1]), dot(rel, axes[2])]
  const closest: Vec3 = [
    clamp(local[0], -half[0], half[0]),
    clamp(local[1], -half[1], half[1]),
    clamp(local[2], -half[2], half[2]),
  ]
  const diff = sub(local, closest)
  const dist = length(diff)

  if (dist >= radius) return null

  let localNormal: Vec3
  let depth: number

  if (dist > 1e-6) {
    localNormal = scale(diff, 1 / dist)
    depth = radius - dist
  } else {
    // The centre is inside the box: leave through the nearest face.
    const face = nearestFace(local, half)
    const sign = local[face.axis] >= 0 ? 1 : -1
    localNormal = [face.axis === 0 ? sign : 0, face.axis === 1 ? sign : 0, face.axis === 2 ? sign : 0]
    depth = radius + face.distance
  }

  const normal = add(
    add(scale(axes[0], localNormal[0]), scale(axes[1], localNormal[1])),
    scale(axes[2], localNormal[2]),
  )

  return {normal, depth}
}

// How a sphere overlaps a round post, or null if it does not.
export const sphereSphereContact = (position: Vec3, radius: number, center: Vec3, size: number): Contact | null => {
  const rel = sub(position, center)
  const dist = length(rel)
  if (dist >= radius + size) return null
  // dead centre: any way out will do, and up is the least surprising
  const normal: Vec3 = dist > 1e-6 ? scale(rel, 1 / dist) : UP
  return {normal, depth: radius + size - dist}
}

interface Placed extends Placement {
  readonly collider: Collider
  readonly index: number
}

interface PlacedContact extends Contact {
  // of the surface touched, at the point touched
  readonly velocity: Vec3
  readonly acceleration: Vec3
  // the bumper's kick, or 0 for anything else
  readonly kick: number
  readonly index: number
}

const contactWith = (position: Vec3, radius: number, item: Placed): Contact | null =>
  item.collider.kind === "bumper"
    ? sphereSphereContact(position, radius, item.center, item.collider.radius)
    : sphereBoxContact(position, radius, item.center, item.collider.half, item.axes)

// How fast the surface of a collider is speeding up at a point on it: the
// change in its slide, plus ω × (ω × r), the pull toward the hub that keeps a
// point on a turntable going round. The slide's change is taken over the
// last `dt`, which is exact for the piecewise-smooth rails movers run on.
const surfaceAccelerationAt = (item: Placed, point: Vec3, time: number, dt: number): Vec3 => {
  const before = colliderAt(item.collider, time - dt).velocity
  const slide = scale(sub(item.velocity, before), 1 / dt)
  const spin = item.angularVelocity
  return add(slide, cross(spin, cross(spin, sub(point, item.center))))
}

const deepestContact = (
  position: Vec3,
  radius: number,
  placed: readonly Placed[],
  time: number,
  dt: number,
): PlacedContact | null => {
  let best: PlacedContact | null = null
  for (const item of placed) {
    const contact = contactWith(position, radius, item)
    if (contact && (!best || contact.depth > best.depth)) {
      const point = addScaled(position, contact.normal, -radius)
      best = {
        ...contact,
        velocity: surfaceVelocityAt(item, point),
        acceleration: surfaceAccelerationAt(item, point, time, dt),
        kick: item.collider.kind === "bumper" ? item.collider.kick : 0,
        index: item.index,
      }
    }
  }
  return best
}

// The bumper's throw: whatever the ball was doing toward it is replaced by a
// fixed speed straight out, across the page. Kept level so a post does not
// launch the ball into the sky, and capped like every other speed.
const kicked = (velocity: Vec3, normal: Vec3, kick: number): Vec3 => {
  const level: Vec3 = [normal[0], 0, normal[2]]
  const size = length(level)
  const out = size > 0.2 ? scale(level, 1 / size) : normal
  const along = dot(velocity, out)
  return along < kick ? addScaled(velocity, out, kick - along) : velocity
}

const capped = (velocity: Vec3): Vec3 => {
  const speed = length(velocity)
  return speed > MAX_SPEED ? scale(velocity, MAX_SPEED / speed) : velocity
}

// One short step, short enough that nothing is jumped over.
const stepOnce = (
  ball: Ball,
  colliders: readonly Collider[],
  time: number,
  gravity: Vec3,
  dt: number,
  radius: number,
): BallStep => {
  let velocity = capped(addScaled(ball.velocity, gravity, dt))
  let position = addScaled(ball.position, velocity, dt)
  let angularVelocity = ball.angularVelocity
  let grounded = false
  let impact = 0
  let surfaceVelocity: Vec3 = ZERO
  let carry: Vec3 = ZERO
  const bumped: number[] = []

  const placed: readonly Placed[] = colliders.map((collider, index) => ({collider, index, ...colliderAt(collider, time)}))

  // Resolving the deepest overlap first matters where two boxes meet flush:
  // the face the ball is sitting on is handled, and the neighbour's edge then
  // no longer overlaps, so seams between platforms do not kick the ball.
  for (let i = 0; i < MAX_CONTACTS_PER_STEP; i++) {
    const contact = deepestContact(position, radius, placed, time, dt)
    if (!contact) break

    const n = contact.normal
    position = addScaled(position, n, contact.depth)

    const relative = sub(velocity, contact.velocity)
    const approach = dot(relative, n)

    if (contact.kick > 0) {
      // A bumper is not something to roll on: no friction, just the throw.
      if (approach < contact.kick) {
        velocity = capped(kicked(velocity, n, contact.kick))
        impact = Math.max(impact, Math.max(0, -approach))
        if (!bumped.includes(contact.index)) bumped.push(contact.index)
      }
      continue
    }

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
      carry = contact.acceleration
    }
  }

  if (grounded) {
    // Drag is measured against whatever the ball is standing on, so a ball
    // at rest on a moving platform stays at rest on it.
    const moving = length(surfaceVelocity) > 1e-6 || length(carry) > 1e-6
    velocity = addScaled(velocity, carry, dt)
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
    bumped,
  }
}

// How many pieces a step of dt must be cut into so that no piece travels
// further than MAX_TRAVEL. The speed is bounded from above by what gravity
// could add during the whole step, so the answer is safe before the step is
// taken. A moving platform can close on the ball too, so its speed counts.
export const splitsFor = (ball: Ball, colliders: readonly Collider[], time: number, gravity: Vec3, dt: number): number => {
  const own = Math.min(MAX_SPEED, length(ball.velocity) + length(gravity) * dt)
  const platforms = colliders.reduce((fastest, collider) => {
    const placement = colliderAt(collider, time)
    // the corner of a turning box is its fastest point
    return Math.max(fastest, length(placement.velocity) + length(placement.angularVelocity) * length(collider.half))
  }, 0)
  const travel = (own + platforms) * dt
  if (!(travel > MAX_TRAVEL)) return 1
  return Math.min(MAX_SPLITS, Math.ceil(travel / MAX_TRAVEL))
}

// Advance the ball by dt seconds. `time` is the clock at the *end* of this
// step, for moving platforms. The impact in the result is for the shell to
// turn into sound.
export const stepBall = (
  ball: Ball,
  colliders: readonly Collider[],
  time: number,
  gravity: Vec3,
  dt: number,
  radius: number = BALL_RADIUS,
): BallStep => {
  const pieces = splitsFor(ball, colliders, time, gravity, dt)
  if (pieces === 1) return stepOnce(ball, colliders, time, gravity, dt, radius)

  const h = dt / pieces
  let result: BallStep = {ball, grounded: false, impact: 0, bumped: []}
  for (let i = 1; i <= pieces; i++) {
    const next = stepOnce(result.ball, colliders, time - dt + i * h, gravity, h, radius)
    result = {
      ball: next.ball,
      grounded: result.grounded || next.grounded,
      impact: Math.max(result.impact, next.impact),
      bumped: [...result.bumped, ...next.bumped.filter(b => !result.bumped.includes(b))],
    }
  }
  return result
}
