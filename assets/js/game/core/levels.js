// The stages, as data.
//
// A stage is a handful of boxes floating in the sky. Each box is described by
// where its *top surface* is, because that is the thing a level designer
// thinks about; `pad` and `slab` turn that into the centre, half-extents and
// orientation the physics and the renderer want.

import {AXES_IDENTITY, addScaled, cross, lerp, length, normalize, sub, UP} from "./math.js"

const THICKNESS = 0.6

// A flat rectangle whose top face is centred on `top`.
export const pad = (top, halfX, halfZ, extra = {}) => ({
  kind: "floor",
  center: [top[0], top[1] - THICKNESS / 2, top[2]],
  half: [halfX, THICKNESS / 2, halfZ],
  axes: AXES_IDENTITY,
  ...extra,
})

// A strip whose top face runs along the line from `from` to `to`. If the two
// ends are at different heights the strip is a ramp.
export const slab = (from, to, width, extra = {}) => {
  const along = normalize(sub(to, from))
  const across = normalize(cross(UP, along))
  const normal = cross(along, across)

  return {
    kind: "floor",
    center: addScaled(lerp(from, to, 0.5), normal, -THICKNESS / 2),
    half: [width / 2, THICKNESS / 2, length(sub(to, from)) / 2],
    axes: [across, normal, along],
    ...extra,
  }
}

// A low kerb to bounce off, standing on a surface at height `base[1]`.
export const wall = (base, halfX, halfZ, height = 0.8) => ({
  kind: "wall",
  center: [base[0], base[1] + height / 2, base[2]],
  half: [halfX, height / 2, halfZ],
  axes: AXES_IDENTITY,
})

// A platform that slides back and forth through `top` along `amplitude`.
export const mover = (top, halfX, halfZ, amplitude, period, phase = 0) =>
  pad(top, halfX, halfZ, {kind: "mover", motion: {amplitude, period, phase}})

const SKIES = {
  morning: {top: [0.42, 0.67, 0.93], bottom: [0.99, 0.9, 0.78]},
  noon: {top: [0.2, 0.55, 0.85], bottom: [0.78, 0.93, 0.96]},
  dusk: {top: [0.36, 0.27, 0.6], bottom: [0.99, 0.72, 0.56]},
}

export const LEVELS = [
  {
    name: "First Page",
    hint: "Drag anywhere to tilt the page",
    time: 60,
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
]

// The height below which a ball is gone for good.
export const killHeight = level =>
  Math.min(...level.platforms.map(p => p.center[1] - Math.abs(p.motion?.amplitude[1] || 0))) - 9
