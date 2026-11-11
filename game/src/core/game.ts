// The rules. `step(state, input, dt)` takes a game state and returns the next
// one; nothing is mutated and nothing outside the arguments is consulted, so
// a run is fully determined by its inputs.
//
// A state moves through phases:
//
//   ready ──▶ playing ──▶ goal ──▶ cleared      (waits for `advance`)
//                │
//                ├──▶ fallout ──▶ ready           (same stage again)
//                └──▶ timeup  ──▶ ready
//
// Things the shell might want to react to (a chime, a buzz) are reported in
// `state.events`, which holds only what happened during the latest step.
//
// Confetti and sparkles are part of the state too, thrown with the core's own
// seeded PRNG, so they replay along with everything else.

import {
  QUAT_IDENTITY,
  ZERO,
  add,
  addScaled,
  angleDelta,
  clamp,
  distance,
  forwardFromYaw,
  length,
  lerp,
  random,
  rightFromYaw,
  scale,
} from "./math.ts"
import {BALL_RADIUS, stepBall} from "./physics.ts"
import {LEVELS, killHeight, levelAt, pageBottom} from "./levels.ts"
import type {Ball, Camera, GameEvent, GameState, Input, Level, Particle, Phase, Vec3} from "./types.ts"

export const GRAVITY = 24
// How far the stage leans at full stick, in radians.
export const MAX_TILT = 0.4
export const READY_TIME = 1.4
export const GOAL_TIME = 1.8
export const RETRY_TIME = 1.6
export const GEM_HEIGHT = 0.85
export const GOAL_RADIUS = 1.25
// For the last part of the countdown the page already leans with the stick,
// though the ball is held, so a player can be set to launch the instant the
// clock starts on "go" instead of waiting for the page to catch up.
export const LAUNCH_GRACE = 0.5
// More than this and the oldest specks go first.
export const MAX_PARTICLES = 120

const SUBSTEPS = 2
const TILT_RESPONSE = 9
const GEM_REACH = BALL_RADIUS + 0.55
const DROP_HEIGHT = 1.2
const CAMERA_TURN = 2.2
const CAMERA_FOLLOW = 10
// Once in the ring the ball's sideways speed is traded, this fast, for a
// gentle pull back to the ring's centre. Plain braking is not enough: a ball
// arriving at full speed would coast a few metres, and on some stages the
// ring is closer to the edge than that.
const GOAL_GRIP = 10
const GOAL_PULL = 3
// Any odd constant would do; each stage mixes in its own number so two stages
// do not throw the same confetti.
const SEED = 0x2545f491

// Specks fall more gently than the ball, and the air slows them.
const PARTICLE_GRAVITY = 9
const PARTICLE_DRAG = 1.6

export type Medal = "gold" | "silver" | "bronze"

const freshBall = (level: Level): Ball => ({
  position: [level.start[0], level.start[1] + BALL_RADIUS + DROP_HEIGHT, level.start[2]],
  velocity: ZERO,
  angularVelocity: ZERO,
  orientation: QUAT_IDENTITY,
})

export const levelCount = (levels: readonly Level[] = LEVELS): number => levels.length

// The opening state of a stage. `banked` is the gem count carried in from
// stages already cleared.
export const startLevel = (levelIndex: number, banked = 0, levels: readonly Level[] = LEVELS): GameState => {
  const level = levelAt(levelIndex, levels)

  return {
    levelIndex,
    phase: "ready",
    phaseTime: 0,
    clock: 0,
    timeLeft: level.time,
    ball: freshBall(level),
    grounded: false,
    tilt: ZERO,
    camera: {yaw: level.startYaw, focus: [level.start[0], level.start[1] + BALL_RADIUS, level.start[2]]},
    collected: level.gems.map(() => false),
    gems: 0,
    banked,
    attempts: 1,
    events: [],
    particles: [],
    seed: (SEED ^ Math.imul(levelIndex + 1, 0x9e3779b1)) | 0,
    speed: 0,
    perfect: false,
  }
}

export const newGame = (levels: readonly Level[] = LEVELS): GameState => startLevel(0, 0, levels)

export const isLastLevel = (state: GameState, levels: readonly Level[] = LEVELS): boolean =>
  state.levelIndex >= levels.length - 1

// From `cleared`: on to the next stage, or back to the first after the last.
export const advance = (state: GameState, levels: readonly Level[] = LEVELS): GameState => {
  if (state.phase !== "cleared") return state
  if (isLastLevel(state, levels)) return newGame(levels)
  return startLevel(state.levelIndex + 1, state.banked + state.gems, levels)
}

// The same stage from the top. The seed carries on, so a retry is not a
// rerun of the same randomness.
export const restart = (state: GameState, levels: readonly Level[] = LEVELS): GameState => ({
  ...startLevel(state.levelIndex, state.banked, levels),
  attempts: state.attempts + 1,
  seed: state.seed,
})

// The best medal a finishing time earns, or null for none.
export const medalFor = (level: Level, seconds: number): Medal | null => {
  if (seconds <= level.par.gold) return "gold"
  if (seconds <= level.par.silver) return "silver"
  if (seconds <= level.par.bronze) return "bronze"
  return null
}

// The pull of gravity for a given lean. The stage never actually rotates in
// the simulation: leaning it by θ is the same as swinging gravity by θ the
// other way, and that keeps every collider static.
export const gravityFor = (tilt: Vec3): Vec3 => {
  const amount = Math.min(1, length(tilt))
  if (amount < 1e-6) return [0, -GRAVITY, 0]

  const angle = amount * MAX_TILT
  const sideways = (Math.sin(angle) * GRAVITY) / amount
  return [tilt[0] * sideways, -Math.cos(angle) * GRAVITY, tilt[2] * sideways]
}

// Stick input is in screen terms (x right, y away from the player); the lean
// it asks for depends on which way the camera is facing.
export const tiltTarget = (input: Input, yaw: number): Vec3 => {
  // `|| 0` also turns a NaN from a confused input device into no lean
  const x = input.x || 0
  const y = input.y || 0
  const size = Math.hypot(x, y)
  const k = size > 1 ? 1 / size : 1
  return add(scale(rightFromYaw(yaw), x * k), scale(forwardFromYaw(yaw), y * k))
}

export const goalCenter = (level: Level): Vec3 => add(level.goal.position, [0, BALL_RADIUS, 0])
export const gemCenter = (gem: Vec3): Vec3 => add(gem, [0, GEM_HEIGHT, 0])

const followCamera = (camera: Camera, ball: Ball, phase: Phase, floor: number, dt: number): Camera => {
  // A ball that has gone over the edge is watched, not chased, whatever the
  // phase says: a camera that follows it down leaves an empty page behind.
  if (phase === "fallout" || ball.position[1] < floor) return camera

  const [vx, , vz] = ball.velocity
  const speed = Math.hypot(vx, vz)
  let yaw = camera.yaw

  if (phase === "playing" && speed > 1) {
    const heading = Math.atan2(-vx, -vz)
    const eagerness = clamp((speed - 1) / 6, 0, 1)
    yaw += angleDelta(yaw, heading) * Math.min(1, CAMERA_TURN * eagerness * dt)
  }

  return {yaw, focus: lerp(camera.focus, ball.position, Math.min(1, CAMERA_FOLLOW * dt))}
}

// --- particles -------------------------------------------------------------

// A non-empty list, so picking from it always finds something.
type Swatch = readonly [Vec3, ...Vec3[]]

interface Burst {
  readonly origin: Vec3
  readonly count: number
  readonly colors: Swatch
  // outward speed of the fastest speck, m/s
  readonly speed: number
  // seconds the longest-lived speck lasts
  readonly life: number
  readonly size: number
}

const GEM_SPARKS: Swatch = [[1, 0.78, 0.18], [1, 0.92, 0.55], [1, 0.97, 0.9]]
const CONFETTI: Swatch = [[0.93, 0.3, 0.24], [1, 0.78, 0.18], [0.2, 0.74, 0.47], [0.36, 0.55, 0.9], [0.92, 0.42, 0.62]]
const BUMPER_SPARKS: Swatch = [[0.92, 0.42, 0.62], [1, 0.97, 0.9]]

// Throw `burst.count` specks out of a point, drawing everything random from
// the seed, and hand back the seed to use next.
const throwBurst = (
  particles: readonly Particle[],
  seed: number,
  burst: Burst,
): {readonly particles: readonly Particle[]; readonly seed: number} => {
  let s = seed
  const draw = (): number => {
    const [value, next] = random(s)
    s = next
    return value
  }

  const thrown = Array.from({length: burst.count}, (): Particle => {
    const heading = draw() * 2 * Math.PI
    // mostly upward: a fountain, not a sphere
    const rise = 0.35 + 0.65 * draw()
    const flat = Math.sqrt(1 - rise * rise)
    const speed = burst.speed * (0.45 + 0.55 * draw())
    const life = burst.life * (0.6 + 0.4 * draw())
    const color = burst.colors[Math.floor(draw() * burst.colors.length)] ?? burst.colors[0]
    return {
      position: burst.origin,
      velocity: scale([Math.cos(heading) * flat, rise, Math.sin(heading) * flat], speed),
      color,
      size: burst.size * (0.7 + 0.6 * draw()),
      life,
      maxLife: life,
    }
  })

  return {particles: [...particles, ...thrown].slice(-MAX_PARTICLES), seed: s}
}

const throwInto = (state: GameState, burst: Burst): GameState => ({...state, ...throwBurst(state.particles, state.seed, burst)})

// Age every speck by dt and let the spent ones go.
export const ageParticles = (particles: readonly Particle[], dt: number): readonly Particle[] => {
  if (particles.length === 0) return particles
  const keep = Math.exp(-PARTICLE_DRAG * dt)
  return particles.flatMap((p): readonly Particle[] => {
    const life = p.life - dt
    if (life <= 0) return []
    const velocity = add(scale(p.velocity, keep), [0, -PARTICLE_GRAVITY * dt, 0])
    return [{...p, life, velocity, position: addScaled(p.position, velocity, dt)}]
  })
}

// --- simulation --------------------------------------------------------------

// `hold` keeps the ball still under a level page while the page itself leans
// toward `tiltGoal`, for the launch grace at the end of the countdown.
const simulate = (state: GameState, level: Level, tiltGoal: Vec3, dt: number, hold = false): GameState => {
  const tilt = lerp(state.tilt, tiltGoal, Math.min(1, TILT_RESPONSE * dt))
  const gravity = gravityFor(hold ? ZERO : tilt)
  const h = dt / SUBSTEPS

  let ball = state.ball
  let clock = state.clock
  let grounded = false
  let impact = 0
  const bumped: number[] = []

  for (let i = 0; i < SUBSTEPS; i++) {
    clock += h
    const result = stepBall(ball, level.platforms, clock, gravity, h)
    ball = result.ball
    grounded = grounded || result.grounded
    impact = Math.max(impact, result.impact)
    bumped.push(...result.bumped.filter(b => !bumped.includes(b)))
  }

  const thud: readonly GameEvent[] =
    impact > 2.5 && bumped.length === 0 ? [{type: "bounce", strength: clamp(impact / 14, 0, 1)}] : []
  const kicks = bumped.map((index): GameEvent => ({type: "bumper", index}))

  const moved: GameState = {
    ...state,
    ball,
    clock,
    tilt,
    grounded,
    speed: Math.hypot(ball.velocity[0], ball.velocity[2]),
    camera: followCamera(state.camera, ball, state.phase, pageBottom(level), dt),
    events: [...thud, ...kicks],
    particles: ageParticles(state.particles, dt),
  }

  return bumped.reduce((next, index) => {
    const post = level.platforms[index]
    if (!post || post.kind !== "bumper") return next
    return throwInto(next, {
      origin: add(post.center, [0, post.radius, 0]),
      count: 8,
      colors: BUMPER_SPARKS,
      speed: 4,
      life: 0.45,
      size: 0.1,
    })
  }, moved)
}

const enter = (state: GameState, phase: Phase, event?: GameEvent): GameState => ({
  ...state,
  phase,
  phaseTime: 0,
  events: event ? [...state.events, event] : state.events,
})

const collectGems = (state: GameState, level: Level): GameState => {
  const hit = level.gems.map(
    (gem, i) => state.collected[i] !== true && distance(state.ball.position, gemCenter(gem)) < GEM_REACH,
  )
  if (!hit.includes(true)) return state

  const collected = state.collected.map((was, i) => was || hit[i] === true)
  const found = hit.flatMap((h, index): readonly GameEvent[] => (h ? [{type: "gem", index}] : []))

  const counted: GameState = {
    ...state,
    collected,
    gems: collected.filter(Boolean).length,
    perfect: collected.length > 0 && collected.every(Boolean),
    events: [...state.events, ...found],
  }

  return level.gems.reduce(
    (next, gem, i) =>
      hit[i] === true
        ? throwInto(next, {origin: gemCenter(gem), count: 12, colors: GEM_SPARKS, speed: 3.5, life: 0.7, size: 0.12})
        : next,
    counted,
  )
}

// Steer the ball's sideways velocity toward one that carries it back to the
// ring's centre, leaving its vertical motion to gravity and the floor.
const catchBall = (ball: Ball, center: Vec3, dt: number): Ball => {
  const k = 1 - Math.exp(-GOAL_GRIP * dt)
  const [vx, vy, vz] = ball.velocity
  const wantX = (center[0] - ball.position[0]) * GOAL_PULL
  const wantZ = (center[2] - ball.position[2]) * GOAL_PULL
  return {...ball, velocity: [vx + (wantX - vx) * k, vy, vz + (wantZ - vz) * k]}
}

const celebrate = (state: GameState, level: Level): GameState =>
  throwInto(state, {
    origin: add(level.goal.position, [0, GOAL_RADIUS * 2, 0]),
    count: 40,
    colors: CONFETTI,
    speed: 7,
    life: 1.6,
    size: 0.16,
  })

export const step = (state: GameState, input: Input, dt: number, levels: readonly Level[] = LEVELS): GameState => {
  const level = levelAt(state.levelIndex, levels)
  const phaseTime = state.phaseTime + dt
  const timed = {...state, phaseTime}

  switch (state.phase) {
    case "ready": {
      // The ball drops onto the page and settles while the player gets set;
      // near the end the page starts to lean with the stick (see LAUNCH_GRACE).
      const leaning = phaseTime >= READY_TIME - LAUNCH_GRACE
      const next = simulate(timed, level, leaning ? tiltTarget(input, state.camera.yaw) : ZERO, dt, true)
      return phaseTime >= READY_TIME ? enter(next, "playing", {type: "go"}) : next
    }

    case "playing": {
      const moved = simulate(timed, level, tiltTarget(input, state.camera.yaw), dt)
      const next = collectGems({...moved, timeLeft: Math.max(0, state.timeLeft - dt)}, level)

      if (distance(next.ball.position, goalCenter(level)) < GOAL_RADIUS) {
        return enter(celebrate(next, level), "goal", {type: "goal"})
      }
      if (next.ball.position[1] < killHeight(level)) return enter(next, "fallout", {type: "fallout"})
      if (next.timeLeft <= 0) return enter(next, "timeup", {type: "timeup"})
      return next
    }

    case "goal": {
      // Level the stage and let the ring catch the ball. The grip goes on
      // before the physics step, so this step already moves at the new speed.
      const caught = {...timed, ball: catchBall(timed.ball, goalCenter(level), dt)}
      const settled = simulate(caught, level, ZERO, dt)
      return phaseTime >= GOAL_TIME ? enter(settled, "cleared") : settled
    }

    case "fallout":
    case "timeup": {
      const next = simulate(timed, level, ZERO, dt)
      return phaseTime >= RETRY_TIME ? restart(state, levels) : next
    }

    case "cleared":
      // Nothing moves until the shell calls `advance`, except the last of
      // the confetti settling.
      return {...state, events: [], particles: ageParticles(state.particles, dt)}

    default: {
      const unreachable: never = state.phase
      return unreachable
    }
  }
}

// Seconds spent on the stage so far, for the results card.
export const elapsed = (state: GameState, levels: readonly Level[] = LEVELS): number =>
  levelAt(state.levelIndex, levels).time - state.timeLeft
