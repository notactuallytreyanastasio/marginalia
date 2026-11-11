// The stages, as data.
//
// A stage is a handful of boxes floating in the sky. Each box is described by
// where its *top surface* is, because that is the thing a level designer
// thinks about; `pad` and `slab` turn that into the centre, half-extents and
// orientation the physics and the renderer want.

import {AXES_IDENTITY, addScaled, cross, lerp, length, normalize, sub, UP} from "./math.ts"
import type {Bumper, Floor, Level, Mover, Rotor, Sky, Vec3, Wall} from "./types.ts"

const THICKNESS = 0.6

// A flat rectangle whose top face is centred on `top`.
export const pad = (top: Vec3, halfX: number, halfZ: number): Floor => ({
  kind: "floor",
  center: [top[0], top[1] - THICKNESS / 2, top[2]],
  half: [halfX, THICKNESS / 2, halfZ],
  axes: AXES_IDENTITY,
})

// A strip whose top face runs along the line from `from` to `to`. If the two
// ends are at different heights the strip is a ramp.
export const slab = (from: Vec3, to: Vec3, width: number): Floor => {
  const along = normalize(sub(to, from))
  const across = normalize(cross(UP, along))
  const normal = cross(along, across)

  return {
    kind: "floor",
    center: addScaled(lerp(from, to, 0.5), normal, -THICKNESS / 2),
    half: [width / 2, THICKNESS / 2, length(sub(to, from)) / 2],
    axes: [across, normal, along],
  }
}

// A low kerb to bounce off, standing on a surface at height `base[1]`.
export const wall = (base: Vec3, halfX: number, halfZ: number, height = 0.8): Wall => ({
  kind: "wall",
  center: [base[0], base[1] + height / 2, base[2]],
  half: [halfX, height / 2, halfZ],
  axes: AXES_IDENTITY,
})

// A platform that slides back and forth through `top` along `amplitude`.
export const mover = (top: Vec3, halfX: number, halfZ: number, amplitude: Vec3, period: number, phase = 0): Mover => ({
  ...pad(top, halfX, halfZ),
  kind: "mover",
  motion: {amplitude, period, phase},
})

// A platform that turns in place about the vertical through `top`, at
// `rate` radians a second (positive is counter-clockwise from above). At
// `phase` 0 its long side, `halfZ`, runs along z.
export const rotor = (top: Vec3, halfX: number, halfZ: number, rate: number, phase = 0): Rotor => ({
  ...pad(top, halfX, halfZ),
  kind: "rotor",
  spin: {rate, phase},
})

// A turntable shaped like a plus sign: two rotors on one hub, a quarter turn
// apart, so an arm comes round four times a revolution.
export const turntable = (top: Vec3, halfWidth: number, reach: number, rate: number, phase = 0): readonly [Rotor, Rotor] => [
  rotor(top, halfWidth, reach, rate, phase),
  rotor(top, halfWidth, reach, rate, phase + Math.PI / 2),
]

// A round post sitting on a surface at `base`, that throws the ball off at
// `kick` m/s.
export const bumper = (base: Vec3, radius = 0.5, kick = 7): Bumper => ({
  kind: "bumper",
  center: [base[0], base[1] + radius, base[2]],
  half: [radius, radius, radius],
  axes: AXES_IDENTITY,
  radius,
  kick,
})

// Points evenly spaced along a line, for strings of gems.
const along = (from: Vec3, to: Vec3, count: number): readonly Vec3[] =>
  Array.from({length: count}, (_, i) => lerp(from, to, count > 1 ? i / (count - 1) : 0.5))

const SKIES = {
  morning: {top: [0.42, 0.67, 0.93], bottom: [0.99, 0.9, 0.78]},
  noon: {top: [0.2, 0.55, 0.85], bottom: [0.78, 0.93, 0.96]},
  dusk: {top: [0.36, 0.27, 0.6], bottom: [0.99, 0.72, 0.56]},
  overcast: {top: [0.45, 0.55, 0.68], bottom: [0.93, 0.92, 0.88]},
  sunset: {top: [0.55, 0.3, 0.5], bottom: [1.0, 0.8, 0.5]},
  night: {top: [0.1, 0.12, 0.3], bottom: [0.45, 0.4, 0.62]},
} as const satisfies Record<string, Sky>

// Par times are set from the scripted player in the tests, which drives
// carefully rather than fast (8.2s, 15.6s, 20.1s, 21.5s, 17.7s and 30.3s):
// gold asks for a little better than it manages, bronze leaves room for a
// wrong turn or two, or a missed turntable arm.
export const LEVELS: readonly Level[] = [
  {
    name: "First Page",
    hint: "Drag anywhere to tilt the page",
    time: 60,
    par: {gold: 8, silver: 12, bronze: 20},
    sky: SKIES.morning,
    start: [0, 0, 1.5],
    startYaw: 0,
    goal: {position: [17, 0, -24], yaw: Math.PI / 2},
    platforms: [
      pad([0, 0, -12], 4, 16),
      pad([12, 0, -24], 8, 4),
      // kerbs on the outside of the corner, to learn the turn against
      wall([0, 0, -27.7], 4, 0.3),
      wall([-3.7, 0, -23.7], 0.3, 3.7),
    ],
    gems: [
      [0, 0, -4],
      [0, 0, -9],
      [0, 0, -14],
      [2.4, 0, -11.5],
      [-2.4, 0, -19],
      [5, 0, -24],
      [9, 0, -24],
      [13, 0, -24],
    ],
  },
  {
    name: "Fold",
    hint: "Ease off before the narrow parts",
    time: 60,
    par: {gold: 15, silver: 22, bronze: 32},
    sky: SKIES.noon,
    start: [0, 0, 0.5],
    startYaw: 0,
    goal: {position: [1.5, -0.5, -30], yaw: Math.PI / 2},
    platforms: [
      pad([0, 0, 0], 3, 3),
      slab([0, 0, -3], [0, -2, -11], 4),
      pad([0, -2, -14], 3, 3),
      slab([3, -2, -14], [13, -2, -14], 2.2),
      pad([16, -2, -14], 3, 3),
      slab([16, -2, -17], [16, -2, -27], 1.8),
      pad([16, -2, -30], 3, 3),
      slab([13, -2, -30], [5, -0.5, -30], 3),
      pad([2, -0.5, -30], 3, 3),
    ],
    gems: [
      [0, -0.75, -6],
      [0, -1.5, -9],
      [5.5, -2, -14],
      [8, -2, -14],
      [10.5, -2, -14],
      [16, -2, -19.5],
      [16, -2, -22],
      [16, -2, -24.5],
      [10.5, -1.53, -30],
      [7.5, -0.97, -30],
    ],
  },
  {
    name: "Loose Leaf",
    hint: "Wait for the page to come to you",
    time: 75,
    par: {gold: 19, silver: 28, bronze: 40},
    sky: SKIES.dusk,
    start: [0, 0, 0.5],
    startYaw: 0,
    goal: {position: [-12, 3, -37], yaw: 0},
    platforms: [
      pad([0, 0, 0], 3, 3),
      slab([0, 0, -3], [0, 0, -9], 3),
      // ferries across the gap: flush with the strip at one end of its
      // travel and with the far landing at the other
      mover([0, 0, -16], 2, 2, [0, 0, 5], 7, Math.PI / 2),
      pad([0, 0, -26], 3, 3),
      slab([-3, 0, -26], [-9, 0, -26], 2.2),
      pad([-12, 0, -26], 3, 3),
      // a lift: level with the landing at the bottom, with the summit on top
      mover([-12, 1.5, -31], 2, 2, [0, 1.5, 0], 6, -Math.PI / 2),
      pad([-12, 3, -36], 3, 3),
    ],
    gems: [
      [0, 0, -5],
      [0, 0, -7.5],
      [0, 0, -13],
      [0, 0, -16],
      [0, 0, -19],
      [-5, 0, -26],
      [-7.5, 0, -26],
      [-12, 0, -24.5],
      [-12, 3, -31],
      [-12, 3, -34.5],
    ],
  },
  {
    // One idea: a turntable. Ride an arm in to the hub, where nothing moves,
    // and wait there for an arm to point the way out.
    name: "Turntable",
    hint: "The middle stands still",
    time: 70,
    par: {gold: 21, silver: 30, bronze: 45},
    sky: SKIES.overcast,
    start: [0, 0, 0.5],
    startYaw: 0,
    goal: {position: [15, 0, -37], yaw: 0},
    platforms: [
      pad([0, 0, 0], 3, 3),
      slab([0, 0, -3], [0, 0, -9.7], 3),
      // arms reach 6 from the hub; the strips stop 6.3 out, so a corner
      // sweeping past never touches them
      ...turntable([0, 0, -16], 1.4, 6, 0.35),
      slab([6.3, 0, -16], [12, 0, -16], 2.4),
      pad([15, 0, -16], 3, 3),
      slab([15, 0, -19], [15, 0, -19.7], 2.4),
      // a single bar the other way round, and quicker: it lines up twice a
      // turn, not four times
      rotor([15, 0, -26], 1.3, 6, -0.45),
      pad([15, 0, -35.3], 3, 3),
    ],
    gems: [
      ...along([0, 0, -5], [0, 0, -8.5], 2),
      [0, 0, -11.5],
      [0, 0, -14.5],
      [3, 0, -16],
      [9, 0, -16],
      [15, 0, -21.5],
      [15, 0, -24.5],
      [15, 0, -30.5],
    ],
  },
  {
    // One idea: posts that throw the ball, on a strip barely wide enough to
    // weave between them.
    name: "Margin Notes",
    hint: "Thread the gaps, don't touch",
    time: 60,
    par: {gold: 17, silver: 25, bronze: 38},
    sky: SKIES.sunset,
    start: [0, 0, 0.5],
    startYaw: 0,
    goal: {position: [-20, 0, -30], yaw: Math.PI / 2},
    platforms: [
      pad([0, 0, 0], 3, 3),
      slab([0, 0, -3], [0, 0, -27], 3),
      bumper([0.75, 0, -8]),
      bumper([-0.75, 0, -12]),
      bumper([0.75, 0, -16]),
      bumper([-0.75, 0, -20]),
      bumper([0.75, 0, -24]),
      pad([0, 0, -30], 3, 3),
      slab([-3, 0, -30], [-17, 0, -30], 3.6),
      // down the middle this time: pass on either side
      bumper([-6.5, 0, -30], 0.4),
      bumper([-10, 0, -30.9], 0.4),
      bumper([-13.5, 0, -30], 0.4),
      pad([-20, 0, -30], 3, 3),
    ],
    gems: [
      [-0.8, 0, -8],
      [0.8, 0, -12],
      [-0.8, 0, -16],
      [0.8, 0, -20],
      [-0.8, 0, -24],
      [-6.5, 0, -31.3],
      [-10, 0, -29.3],
      [-13.5, 0, -31.3],
    ],
  },
  {
    // Everything at once: down a ramp, across on the ferry, up to a turning
    // bar, and from its hub up the last climb.
    name: "Last Word",
    hint: "Everything you have learned",
    time: 90,
    par: {gold: 30, silver: 42, bronze: 60},
    sky: SKIES.night,
    start: [0, 2, 0.5],
    startYaw: 0,
    goal: {position: [15.3, 3, -52], yaw: 0},
    platforms: [
      pad([0, 2, 0], 3, 3),
      slab([0, 2, -3], [0, 0, -11], 3),
      pad([0, 0, -14], 3, 3),
      // in dock against the pad at the top of its travel, against the far
      // landing at the bottom
      mover([0, 0, -24], 2, 2, [0, 0, 5], 7, Math.PI / 2),
      pad([0, 0, -34], 3, 3),
      slab([3, 0, -34], [9, 1, -34], 2.4),
      rotor([15.3, 1, -34], 1.3, 6, 0.4, Math.PI / 2),
      slab([15.3, 1, -40.3], [15.3, 3, -48], 2.4),
      pad([15.3, 3, -51], 3, 3),
    ],
    gems: [
      [0, 1.25, -6],
      [0, 0.5, -9],
      [0, 0, -16.5],
      [0, 0, -24],
      [0, 0, -32],
      [6, 0.5, -34],
      [15.3, 1, -34],
      [15.3, 1.56, -42.5],
      [15.3, 2.44, -45.8],
    ],
  },
]

// A stage by number. Asking for one that does not exist is a bug in the
// caller, not a state the game can be in, so it throws.
export const levelAt = (index: number, levels: readonly Level[] = LEVELS): Level => {
  const level = levels[index]
  if (!level) throw new RangeError(`no level ${index} (there are ${levels.length})`)
  return level
}

// The height below which a ball is gone for good.
export const killHeight = (level: Level): number =>
  Math.min(...level.platforms.map(p => p.center[1] - (p.kind === "mover" ? Math.abs(p.motion.amplitude[1]) : 0))) - 9
