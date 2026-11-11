// The shapes the whole game is built from. Everything is readonly: the core
// never changes a value it was given, it returns a new one, and these types
// make the checker hold it to that.

export type Vec3 = readonly [number, number, number]
// [x, y, z, w]
export type Quat = readonly [number, number, number, number]
// Column-major, the layout WebGL expects.
export type Mat4 = readonly [
  number, number, number, number,
  number, number, number, number,
  number, number, number, number,
  number, number, number, number,
]
// The three directions a box's local x, y and z point in, in world space.
export type Axes = readonly [Vec3, Vec3, Vec3]

// --- the world -------------------------------------------------------------

// A platform slides through its rest position along `amplitude` and back
// once every `period` seconds, starting `phase` radians into the cycle.
export interface Motion {
  readonly amplitude: Vec3
  readonly period: number
  readonly phase: number
}

interface Box {
  readonly center: Vec3
  readonly half: Vec3
  readonly axes: Axes
}

export interface Floor extends Box {
  readonly kind: "floor"
}

export interface Wall extends Box {
  readonly kind: "wall"
}

export interface Mover extends Box {
  readonly kind: "mover"
  readonly motion: Motion
}

// A turntable turns about the vertical line through its centre at `rate`
// radians a second (positive is counter-clockwise seen from above), starting
// `phase` radians round from the orientation in `axes`.
export interface Spin {
  readonly rate: number
  readonly phase: number
}

export interface Rotor extends Box {
  readonly kind: "rotor"
  readonly spin: Spin
}

// A post that throws the ball off at `kick` m/s. It is a sphere of `radius`;
// `half` and `axes` are its bounding cube, so anything that only wants a box
// round every collider still has one.
export interface Bumper extends Box {
  readonly kind: "bumper"
  readonly radius: number
  readonly kick: number
}

export type Collider = Floor | Wall | Mover | Rotor | Bumper
// Every collider in a level is a platform of some kind; the two names are
// kept because physics thinks in colliders and level design in platforms.
export type Platform = Collider

export interface Sky {
  readonly top: Vec3
  readonly bottom: Vec3
}

export interface Goal {
  readonly position: Vec3
  readonly yaw: number
}

// Seconds to finish a stage for each medal. gold < silver < bronze.
export interface Par {
  readonly gold: number
  readonly silver: number
  readonly bronze: number
}

export interface Level {
  readonly name: string
  readonly hint: string
  // seconds on the clock
  readonly time: number
  readonly par: Par
  readonly sky: Sky
  readonly start: Vec3
  readonly startYaw: number
  readonly goal: Goal
  readonly platforms: readonly Platform[]
  readonly gems: readonly Vec3[]
}

// --- the game --------------------------------------------------------------

export interface Ball {
  readonly position: Vec3
  readonly velocity: Vec3
  readonly angularVelocity: Vec3
  readonly orientation: Quat
}

export type Phase = "ready" | "playing" | "goal" | "cleared" | "fallout" | "timeup"

export type GameEvent =
  | {readonly type: "go"}
  | {readonly type: "gem"; readonly index: number}
  | {readonly type: "goal"}
  | {readonly type: "fallout"}
  | {readonly type: "timeup"}
  // strength 0..1, for the volume of a thud
  | {readonly type: "bounce"; readonly strength: number}
  // `index` is the bumper's place in the level's platforms
  | {readonly type: "bumper"; readonly index: number}

export type GameEventType = GameEvent["type"]

export interface Camera {
  readonly yaw: number
  readonly focus: Vec3
}

// A speck of confetti, dust or sparkle. `life` counts down from `maxLife`
// to 0, in seconds.
export interface Particle {
  readonly position: Vec3
  readonly velocity: Vec3
  readonly color: Vec3
  readonly size: number
  readonly life: number
  readonly maxLife: number
}

export interface GameState {
  readonly levelIndex: number
  readonly phase: Phase
  readonly phaseTime: number
  // Seconds since the stage was (re)started; drives moving platforms.
  readonly clock: number
  readonly timeLeft: number
  readonly ball: Ball
  readonly grounded: boolean
  // Lean of the stage as a world-space vector on the ground plane, 0..1.
  readonly tilt: Vec3
  readonly camera: Camera
  readonly collected: readonly boolean[]
  readonly gems: number
  readonly banked: number
  readonly attempts: number
  // Only what happened during the latest step.
  readonly events: readonly GameEvent[]
  readonly particles: readonly Particle[]
  // State for the core's PRNG, so randomness replays with everything else.
  readonly seed: number
  // Ball speed across the stage (ignoring up and down), m/s, for the HUD.
  readonly speed: number
  // Every gem on the stage has been picked up this attempt.
  readonly perfect: boolean
}

// Stick position, each -1..1: x to the right, y away from the player.
export interface Input {
  readonly x: number
  readonly y: number
}

// --- the picture -----------------------------------------------------------

export type MeshName = "box" | "sphere" | "torus" | "gem" | "cylinder" | "disc"

// How the toon shader colours a surface.
//   plain  one flat colour
//   paper  squared paper on top (color, lines in color2), cut edges in color3
//   ball   two halves (color, color3) and a belt (color2)
export type Pattern = "plain" | "paper" | "ball"

export interface MeshData {
  readonly positions: Float32Array
  readonly normals: Float32Array
  // per-vertex normal shared by every face meeting at that corner, for the outline
  readonly smooth: Float32Array
  readonly indices: Uint16Array
}

export type Meshes = Readonly<Record<MeshName, MeshData>>

export interface SceneItem {
  readonly mesh: MeshName
  readonly model: Mat4
  readonly scale: Vec3
  readonly pattern: Pattern
  readonly color: Vec3
  readonly color2: Vec3
  readonly color3: Vec3
  // outline width as a fraction of depth; 0 for none
  readonly outline: number
  readonly castsShadow: boolean
}

export interface SceneParticle {
  readonly position: Vec3
  readonly color: Vec3
  readonly size: number
  // 0..1
  readonly alpha: number
}

export interface Scene {
  readonly viewProjection: Mat4
  readonly eye: Vec3
  // unit vector toward the light
  readonly light: Vec3
  readonly sky: Sky
  readonly ball: {readonly position: Vec3; readonly radius: number}
  readonly items: readonly SceneItem[]
  readonly particles: readonly SceneParticle[]
  // seconds on the stage clock, for anything in a shader that moves
  readonly time: number
}
