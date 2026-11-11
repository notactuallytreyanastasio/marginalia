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

import {
  QUAT_IDENTITY,
  add,
  addScaled,
  angleDelta,
  clamp,
  distance,
  forwardFromYaw,
  length,
  lerp,
  rightFromYaw,
  scale,
} from "./math.js"
import {BALL_RADIUS, stepBall} from "./physics.js"
import {LEVELS, killHeight} from "./levels.js"

export const GRAVITY = 24
// How far the stage leans at full stick, in radians.
export const MAX_TILT = 0.4
export const READY_TIME = 1.4
export const GOAL_TIME = 1.8
export const RETRY_TIME = 1.6
export const GEM_HEIGHT = 0.85
export const GOAL_RADIUS = 1.25

const SUBSTEPS = 2
const TILT_RESPONSE = 9
const GEM_REACH = BALL_RADIUS + 0.55
const DROP_HEIGHT = 1.2
const CAMERA_TURN = 2.2
const CAMERA_FOLLOW = 10

const freshBall = level => ({
  position: [level.start[0], level.start[1] + BALL_RADIUS + DROP_HEIGHT, level.start[2]],
  velocity: [0, 0, 0],
  angularVelocity: [0, 0, 0],
  orientation: QUAT_IDENTITY,
})

// The opening state of a stage. `banked` is the gem count carried in from
// stages already cleared.
export const startLevel = (levelIndex, banked = 0, levels = LEVELS) => {
  const level = levels[levelIndex]
  const ball = freshBall(level)

  return {
    levelIndex,
    phase: "ready",
    phaseTime: 0,
    // Seconds since the stage was (re)started; drives moving platforms.
    clock: 0,
    timeLeft: level.time,
    ball,
    grounded: false,
    // Lean of the stage as a world-space vector on the ground plane, 0..1.
    tilt: [0, 0, 0],
    camera: {yaw: level.startYaw, focus: [level.start[0], level.start[1] + BALL_RADIUS, level.start[2]]},
    collected: level.gems.map(() => false),
    gems: 0,
    banked,
    attempts: 1,
    events: [],
  }
}

export const newGame = (levels = LEVELS) => startLevel(0, 0, levels)

export const isLastLevel = (state, levels = LEVELS) => state.levelIndex >= levels.length - 1

// From `cleared`: on to the next stage, or back to the first after the last.
export const advance = (state, levels = LEVELS) => {
  if (state.phase !== "cleared") return state
  if (isLastLevel(state, levels)) return newGame(levels)
  return startLevel(state.levelIndex + 1, state.banked + state.gems, levels)
}

export const restart = (state, levels = LEVELS) => ({
  ...startLevel(state.levelIndex, state.banked, levels),
  attempts: state.attempts + 1,
})

// The pull of gravity for a given lean. The stage never actually rotates in
// the simulation: leaning it by θ is the same as swinging gravity by θ the
// other way, and that keeps every collider static.
export const gravityFor = tilt => {
  const amount = Math.min(1, length(tilt))
  if (amount < 1e-6) return [0, -GRAVITY, 0]

  const angle = amount * MAX_TILT
  const sideways = (Math.sin(angle) * GRAVITY) / amount
  return [tilt[0] * sideways, -Math.cos(angle) * GRAVITY, tilt[2] * sideways]
}

// Stick input is in screen terms (x right, y away from the player); the lean
// it asks for depends on which way the camera is facing.
export const tiltTarget = (input, yaw) => {
  const x = input?.x || 0
  const y = input?.y || 0
  const size = Math.hypot(x, y)
  const k = size > 1 ? 1 / size : 1
  return add(scale(rightFromYaw(yaw), x * k), scale(forwardFromYaw(yaw), y * k))
}

export const goalCenter = level => add(level.goal.position, [0, BALL_RADIUS, 0])
export const gemCenter = gem => add(gem, [0, GEM_HEIGHT, 0])

const followCamera = (camera, ball, phase, dt) => {
  // A ball that has gone over the edge is watched, not chased.
  if (phase === "fallout") return camera

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

const simulate = (state, level, tiltGoal, dt) => {
  const tilt = lerp(state.tilt, tiltGoal, Math.min(1, TILT_RESPONSE * dt))
  const gravity = gravityFor(tilt)
  const h = dt / SUBSTEPS

  let ball = state.ball
  let clock = state.clock
  let grounded = false
  let impact = 0

  for (let i = 0; i < SUBSTEPS; i++) {
    clock += h
    const result = stepBall(ball, level.platforms, clock, gravity, h)
    ball = result.ball
    grounded = grounded || result.grounded
    impact = Math.max(impact, result.impact)
  }

  const events = impact > 2.5 ? [{type: "bounce", strength: clamp(impact / 14, 0, 1)}] : []

  return {
    ...state,
    ball,
    clock,
    tilt,
    grounded,
    camera: followCamera(state.camera, ball, state.phase, dt),
    events,
  }
}

const enter = (state, phase, event) => ({
  ...state,
  phase,
  phaseTime: 0,
  events: event ? [...state.events, event] : state.events,
})

const collectGems = (state, level) => {
  let collected = state.collected
  let events = state.events

  level.gems.forEach((gem, i) => {
    if (!collected[i] && distance(state.ball.position, gemCenter(gem)) < GEM_REACH) {
      if (collected === state.collected) collected = [...collected]
      collected[i] = true
      events = [...events, {type: "gem", index: i}]
    }
  })

  if (collected === state.collected) return state
  return {...state, collected, gems: collected.filter(Boolean).length, events}
}

export const step = (state, input, dt, levels = LEVELS) => {
  const level = levels[state.levelIndex]
  const phaseTime = state.phaseTime + dt
  const timed = {...state, phaseTime}

  switch (state.phase) {
    case "ready": {
      // The ball drops onto the page and settles while the player gets set.
      const next = simulate(timed, level, [0, 0, 0], dt)
      return phaseTime >= READY_TIME ? enter(next, "playing", {type: "go"}) : next
    }

    case "playing": {
      const moved = simulate(timed, level, tiltTarget(input, state.camera.yaw), dt)
      const next = collectGems({...moved, timeLeft: Math.max(0, state.timeLeft - dt)}, level)

      if (distance(next.ball.position, goalCenter(level)) < GOAL_RADIUS) {
        return enter(next, "goal", {type: "goal"})
      }
      if (next.ball.position[1] < killHeight(level)) return enter(next, "fallout", {type: "fallout"})
      if (next.timeLeft <= 0) return enter(next, "timeup", {type: "timeup"})
      return next
    }

    case "goal": {
      // Level the stage and let the ball coast to a stop.
      const coasting = simulate(timed, level, [0, 0, 0], dt)
      const braked = {
        ...coasting,
        ball: {...coasting.ball, velocity: scale(coasting.ball.velocity, Math.exp(-3 * dt))},
      }
      return phaseTime >= GOAL_TIME ? enter(braked, "cleared") : braked
    }

    case "fallout":
    case "timeup": {
      const next = simulate(timed, level, [0, 0, 0], dt)
      return phaseTime >= RETRY_TIME ? restart(state, levels) : next
    }

    default:
      return {...state, events: []}
  }
}

// Seconds spent on the stage so far, for the results card.
export const elapsed = (state, levels = LEVELS) => levels[state.levelIndex].time - state.timeLeft
