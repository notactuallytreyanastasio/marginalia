// From a game state to a description of the picture: a camera and a flat list
// of things to draw. Still pure — the renderer walks this list and never
// looks at the game state itself, and a test can read it without a GPU.

import {
  UP,
  add,
  addScaled,
  axesFromYaw,
  cross,
  forwardFromYaw,
  length,
  mat4FromAxisAngle,
  mat4FromBasis,
  mat4LookAt,
  mat4Multiply,
  mat4Perspective,
  mat4Translation,
  quatToAxes,
  scale,
} from "./math.js"
import {BALL_RADIUS, colliderAt} from "./physics.js"
import {GEM_HEIGHT, GOAL_RADIUS, MAX_TILT} from "./game.js"
import {LEVELS} from "./levels.js"

export const PATTERN = {plain: 0, paper: 1, ball: 2}

const PALETTE = {
  paper: {color: [0.98, 0.96, 0.9], color2: [0.6, 0.73, 0.9], color3: [0.84, 0.77, 0.65]},
  mover: {color: [1.0, 0.92, 0.68], color2: [0.93, 0.62, 0.4], color3: [0.85, 0.68, 0.38]},
  wall: [0.18, 0.6, 0.62],
  ball: {color: [0.93, 0.3, 0.24], color2: [1, 0.97, 0.9], color3: [0.7, 0.16, 0.22]},
  gem: [1, 0.78, 0.18],
  goal: [0.2, 0.74, 0.47],
  goalDone: [1, 0.78, 0.18],
}

const LIGHT = [0.42, 0.84, 0.34]
// How much of the simulated lean is shown. Leaning forward lifts the ground
// behind the ball toward the camera, and a downhill ramp lifts it further;
// shown in full, the two together put the camera under the floor. About half
// reads clearly as a tilt and leaves the camera room above the steepest ramp.
const VISIBLE_TILT = 0.55
const OUTLINE = 0.0036

const cameraFor = (state, aspect) => {
  // Held upright, a phone sees a tall narrow slice: widen the lens, climb,
  // and look further down the path, which also lifts the ball clear of the
  // thumb at the bottom of the screen.
  const portrait = aspect < 1
  const fov = ((portrait ? 62 : 50) * Math.PI) / 180
  const back = portrait ? 8.2 : 7.4
  const height = portrait ? 6.2 : 4.8
  const lead = portrait ? 3.2 : 2.2

  const {yaw, focus} = state.camera
  const forward = forwardFromYaw(yaw)
  const eye = add(addScaled(focus, forward, -back), [0, height, 0])
  const target = state.phase === "fallout" ? state.ball.position : addScaled(focus, forward, lead)

  return {eye, target, fov}
}

// The lean of the stage, as a rotation about the point under the camera.
const tiltMatrix = (tilt, pivot) => {
  const amount = Math.min(1, length(tilt))
  if (amount < 1e-4) return null

  const rotation = mat4FromAxisAngle(cross(UP, tilt), amount * MAX_TILT * VISIBLE_TILT)
  return mat4Multiply(mat4Translation(pivot), mat4Multiply(rotation, mat4Translation(scale(pivot, -1))))
}

const platformItem = (platform, clock) => {
  const {center} = colliderAt(platform, clock)
  const model = mat4FromBasis(center, platform.axes)

  if (platform.kind === "wall") {
    return {mesh: "box", model, scale: platform.half, pattern: PATTERN.plain, color: PALETTE.wall, outline: OUTLINE}
  }

  const palette = platform.kind === "mover" ? PALETTE.mover : PALETTE.paper
  return {mesh: "box", model, scale: platform.half, pattern: PATTERN.paper, ...palette, outline: OUTLINE}
}

const gemItem = (gem, index, clock) => {
  const bob = Math.sin(clock * 2.4 + index) * 0.12
  return {
    mesh: "gem",
    model: mat4FromBasis(add(gem, [0, GEM_HEIGHT + bob, 0]), axesFromYaw(clock * 2 + index)),
    scale: [0.4, 0.4, 0.4],
    pattern: PATTERN.plain,
    color: PALETTE.gem,
    outline: OUTLINE,
  }
}

const goalItems = (goal, reached) => {
  const axes = axesFromYaw(goal.yaw)
  const color = reached ? PALETTE.goalDone : PALETTE.goal
  return [
    {
      mesh: "torus",
      model: mat4FromBasis(add(goal.position, [0, GOAL_RADIUS + 0.1, 0]), axes),
      scale: [GOAL_RADIUS, GOAL_RADIUS, GOAL_RADIUS],
      pattern: PATTERN.plain,
      color,
      outline: OUTLINE,
    },
    {
      mesh: "box",
      model: mat4FromBasis(add(goal.position, [0, 0.02, 0]), axes),
      scale: [GOAL_RADIUS + 0.2, 0.02, 0.35],
      pattern: PATTERN.plain,
      color,
      outline: 0,
    },
  ]
}

export const buildScene = (state, aspect, levels = LEVELS) => {
  const level = levels[state.levelIndex]
  const camera = cameraFor(state, aspect)
  const projection = mat4Perspective(camera.fov, aspect, 0.3, 220)
  const view = mat4LookAt(camera.eye, camera.target)
  const lean = tiltMatrix(state.tilt, state.camera.focus)
  const viewProjection = mat4Multiply(projection, lean ? mat4Multiply(view, lean) : view)
  const reached = state.phase === "goal" || state.phase === "cleared"

  const items = [
    ...level.platforms.map(platform => platformItem(platform, state.clock)),
    ...goalItems(level.goal, reached),
    ...level.gems.flatMap((gem, i) => (state.collected[i] ? [] : [gemItem(gem, i, state.clock)])),
    {
      mesh: "sphere",
      model: mat4FromBasis(state.ball.position, quatToAxes(state.ball.orientation)),
      scale: [BALL_RADIUS, BALL_RADIUS, BALL_RADIUS],
      pattern: PATTERN.ball,
      ...PALETTE.ball,
      outline: OUTLINE,
    },
  ]

  return {
    viewProjection,
    eye: camera.eye,
    light: LIGHT,
    sky: level.sky,
    ball: {position: state.ball.position, radius: BALL_RADIUS},
    items,
  }
}
