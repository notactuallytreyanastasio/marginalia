// From a game state to a description of the picture: a camera and a flat list
// of things to draw. Still pure — the renderer walks this list and never
// looks at the game state itself, and a test can read it without a GPU.

import {
  UP,
  add,
  addScaled,
  axesFromYaw,
  clamp,
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
} from "./math.ts"
import {BALL_RADIUS, colliderAt} from "./physics.ts"
import {GEM_HEIGHT, GOAL_RADIUS, MAX_TILT} from "./game.ts"
import {LEVELS, levelAt} from "./levels.ts"
import type {
  GameState,
  Goal,
  Level,
  Mat4,
  Particle,
  Platform,
  Scene,
  SceneItem,
  SceneParticle,
  Vec3,
} from "./types.ts"

interface Colors {
  readonly color: Vec3
  readonly color2: Vec3
  readonly color3: Vec3
}

// One colour for every channel, for patterns that use only the first.
const flat = (color: Vec3): Colors => ({color, color2: color, color3: color})

const PALETTE = {
  paper: {color: [0.98, 0.96, 0.9], color2: [0.6, 0.73, 0.9], color3: [0.84, 0.77, 0.65]},
  mover: {color: [1.0, 0.92, 0.68], color2: [0.93, 0.62, 0.4], color3: [0.85, 0.68, 0.38]},
  // a cooler sheet than the ferries, so a thing that turns never reads as a
  // thing that slides
  rotor: {color: [0.88, 0.94, 0.98], color2: [0.42, 0.58, 0.86], color3: [0.5, 0.64, 0.82]},
  bumper: flat([0.92, 0.42, 0.62]),
  wall: flat([0.18, 0.6, 0.62]),
  ball: {color: [0.93, 0.3, 0.24], color2: [1, 0.97, 0.9], color3: [0.7, 0.16, 0.22]},
  gem: flat([1, 0.78, 0.18]),
  goal: flat([0.2, 0.74, 0.47]),
  goalDone: flat([1, 0.78, 0.18]),
} as const satisfies Record<string, Colors>

const LIGHT: Vec3 = [0.42, 0.84, 0.34]
// How much of the simulated lean is shown. Leaning forward lifts the ground
// behind the ball toward the camera, and a downhill ramp lifts it further;
// shown in full, the two together put the camera under the floor. About half
// reads clearly as a tilt and leaves the camera room above the steepest ramp.
const VISIBLE_TILT = 0.55
const OUTLINE = 0.0036

interface Lens {
  readonly eye: Vec3
  readonly target: Vec3
  readonly fov: number
}

const cameraFor = (state: GameState, aspect: number): Lens => {
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
const tiltMatrix = (tilt: Vec3, pivot: Vec3): Mat4 | null => {
  const amount = Math.min(1, length(tilt))
  if (amount < 1e-4) return null

  const rotation = mat4FromAxisAngle(cross(UP, tilt), amount * MAX_TILT * VISIBLE_TILT)
  return mat4Multiply(mat4Translation(pivot), mat4Multiply(rotation, mat4Translation(scale(pivot, -1))))
}

const platformItem = (platform: Platform, clock: number): SceneItem => {
  const {center, axes} = colliderAt(platform, clock)
  const placed = {mesh: "box", model: mat4FromBasis(center, axes), scale: platform.half, outline: OUTLINE} as const

  switch (platform.kind) {
    case "bumper":
      return {
        mesh: "sphere",
        model: mat4FromBasis(center, axes),
        scale: [platform.radius, platform.radius, platform.radius],
        pattern: "plain",
        ...PALETTE.bumper,
        outline: OUTLINE,
        castsShadow: true,
      }
    case "rotor":
      return {...placed, pattern: "paper", ...PALETTE.rotor, castsShadow: true}
    case "wall":
      return {...placed, pattern: "plain", ...PALETTE.wall, castsShadow: true}
    case "mover":
      return {...placed, pattern: "paper", ...PALETTE.mover, castsShadow: true}
    case "floor":
      return {...placed, pattern: "paper", ...PALETTE.paper, castsShadow: false}
    default: {
      const unreachable: never = platform
      return unreachable
    }
  }
}

// A cap on the pivot of each turning bar, so the eye can find what it turns
// about. It is paint, like the goal line: no collider, a hair above the top
// face so the ball rolls over it.
const hubItems = (platform: Platform, clock: number): readonly SceneItem[] => {
  if (platform.kind !== "rotor") return []
  const {center, axes} = colliderAt(platform, clock)
  const radius = Math.min(platform.half[0], platform.half[2]) * 0.8
  const top = addScaled(center, axes[1], platform.half[1] + 0.03)
  return [
    {
      mesh: "disc",
      model: mat4FromBasis(top, axes),
      scale: [radius, 0.03, radius],
      pattern: "plain",
      ...flat(PALETTE.rotor.color2),
      outline: 0,
      castsShadow: false,
    },
  ]
}

const gemItem = (gem: Vec3, index: number, clock: number): SceneItem => {
  const bob = Math.sin(clock * 2.4 + index) * 0.12
  return {
    mesh: "gem",
    model: mat4FromBasis(add(gem, [0, GEM_HEIGHT + bob, 0]), axesFromYaw(clock * 2 + index)),
    scale: [0.4, 0.4, 0.4],
    pattern: "plain",
    ...PALETTE.gem,
    outline: OUTLINE,
    castsShadow: true,
  }
}

const goalItems = (goal: Goal, reached: boolean): readonly SceneItem[] => {
  const axes = axesFromYaw(goal.yaw)
  const colors = reached ? PALETTE.goalDone : PALETTE.goal
  return [
    {
      mesh: "torus",
      model: mat4FromBasis(add(goal.position, [0, GOAL_RADIUS + 0.1, 0]), axes),
      scale: [GOAL_RADIUS, GOAL_RADIUS, GOAL_RADIUS],
      pattern: "plain",
      ...colors,
      outline: OUTLINE,
      castsShadow: true,
    },
    // the line painted on the page under the ring
    {
      mesh: "box",
      model: mat4FromBasis(add(goal.position, [0, 0.02, 0]), axes),
      scale: [GOAL_RADIUS + 0.2, 0.02, 0.35],
      pattern: "plain",
      ...colors,
      outline: 0,
      castsShadow: false,
    },
  ]
}

const particleItem = (particle: Particle): SceneParticle => ({
  position: particle.position,
  color: particle.color,
  size: particle.size,
  alpha: particle.maxLife > 0 ? clamp(particle.life / particle.maxLife, 0, 1) : 0,
})

export const buildScene = (state: GameState, aspect: number, levels: readonly Level[] = LEVELS): Scene => {
  const level = levelAt(state.levelIndex, levels)
  const camera = cameraFor(state, aspect)
  const projection = mat4Perspective(camera.fov, aspect, 0.3, 220)
  const view = mat4LookAt(camera.eye, camera.target)
  const lean = tiltMatrix(state.tilt, state.camera.focus)
  const viewProjection = mat4Multiply(projection, lean ? mat4Multiply(view, lean) : view)
  const reached = state.phase === "goal" || state.phase === "cleared"

  const items: readonly SceneItem[] = [
    // platforms first and in level order, so item i is platform i
    ...level.platforms.map(platform => platformItem(platform, state.clock)),
    ...level.platforms.flatMap(platform => hubItems(platform, state.clock)),
    ...goalItems(level.goal, reached),
    ...level.gems.flatMap((gem, i) => (state.collected[i] === true ? [] : [gemItem(gem, i, state.clock)])),
    {
      mesh: "sphere",
      model: mat4FromBasis(state.ball.position, quatToAxes(state.ball.orientation)),
      scale: [BALL_RADIUS, BALL_RADIUS, BALL_RADIUS],
      pattern: "ball",
      ...PALETTE.ball,
      outline: OUTLINE,
      castsShadow: true,
    },
  ]

  return {
    viewProjection,
    eye: camera.eye,
    light: LIGHT,
    sky: level.sky,
    ball: {position: state.ball.position, radius: BALL_RADIUS},
    items,
    particles: state.particles.map(particleItem),
    time: state.clock,
  }
}
