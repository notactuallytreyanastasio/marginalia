// Run with: npm test
//
// The core has no canvas and no clock of its own, so whole runs can be played
// here: every stage is finished by a scripted player below, which is the
// proof that each one can be.

import test from "node:test"
import assert from "node:assert/strict"

import {
  add,
  angleDelta,
  dot,
  forwardFromYaw,
  length,
  mat4FromBasis,
  mat4LookAt,
  mat4Multiply,
  mat4Perspective,
  mat4TransformPoint,
  normalize,
  random,
  rightFromYaw,
  scale,
  sub,
} from "../src/core/math.ts"
import {BALL_RADIUS, MAX_SPEED, colliderAt, sphereBoxContact, splitsFor, stepBall, surfaceVelocityAt} from "../src/core/physics.ts"
import type {Contact} from "../src/core/physics.ts"
import {LEVELS, bumper, killHeight, levelAt, mover, pad, rotor, slab, wall} from "../src/core/levels.ts"
import {
  GOAL_TIME,
  GRAVITY,
  LAUNCH_GRACE,
  MAX_PARTICLES,
  MAX_TILT,
  READY_TIME,
  advance,
  elapsed,
  goalCenter,
  gravityFor,
  levelCount,
  medalFor,
  newGame,
  restart,
  startLevel,
  step,
} from "../src/core/game.ts"
import {buildMeshes} from "../src/core/meshes.ts"
import {buildScene} from "../src/core/scene.ts"
import type {Ball, GameEvent, GameEventType, GameState, Input, Level, Platform, Vec3} from "../src/core/types.ts"

const DT = 1 / 60
const near = (a: number, b: number, eps = 1e-6): boolean => Math.abs(a - b) < eps

const restingBall = (position: Vec3): Ball => ({
  position,
  velocity: [0, 0, 0],
  angularVelocity: [0, 0, 0],
  orientation: [0, 0, 0, 1],
})

const run = (state: GameState, input: Input, seconds: number, levels?: readonly Level[]): GameState => {
  for (let i = 0; i < Math.round(seconds / DT); i++) state = step(state, input, DT, levels)
  return state
}

// A contact the test expects to exist.
const touching = (contact: Contact | null): Contact => {
  assert.ok(contact, "expected a contact")
  return contact
}

const platform = (level: Level, index: number): Platform => {
  const p = level.platforms[index]
  assert.ok(p, `${level.name} has no platform ${index}`)
  return p
}

// --- math ------------------------------------------------------------------

test("angleDelta takes the short way round", () => {
  assert.ok(near(angleDelta(0.1, -0.1), -0.2))
  assert.ok(near(angleDelta(3, -3), 2 * Math.PI - 6))
})

test("a point in front of the camera projects to the middle of the screen", () => {
  const viewProjection = mat4Multiply(mat4Perspective(1, 1.5, 0.1, 100), mat4LookAt([0, 2, 5], [0, 0, 0]))
  const [x, y, z] = mat4TransformPoint(viewProjection, [0, 0, 0])
  assert.ok(near(x, 0) && near(y, 0))
  assert.ok(z > -1 && z < 1)
})

test("a basis matrix carries local axes onto the given ones", () => {
  const m = mat4FromBasis([1, 2, 3], [[0, 0, -1], [0, 1, 0], [1, 0, 0]])
  assert.deepEqual(mat4TransformPoint(m, [1, 0, 0]), [1, 2, 2])
})

test("the PRNG is a pure function of its seed, spread over [0, 1)", () => {
  assert.deepEqual(random(42), random(42))

  let seed = 7
  const values: number[] = []
  for (let i = 0; i < 2000; i++) {
    const [value, next] = random(seed)
    values.push(value)
    assert.notEqual(next, seed)
    seed = next
  }

  assert.ok(values.every(v => v >= 0 && v < 1))
  const mean = values.reduce((a, b) => a + b, 0) / values.length
  assert.ok(Math.abs(mean - 0.5) < 0.03, `mean ${mean}`)
  assert.ok(new Set(values).size > 1990, "and does not repeat itself")
})

// --- physics ---------------------------------------------------------------

test("a sphere above a box does not touch it; one sunk into it is pushed up", () => {
  const box = pad([0, 0, 0], 2, 2)
  assert.equal(sphereBoxContact([0, 0.6, 0], 0.5, box.center, box.half, box.axes), null)

  const contact = touching(sphereBoxContact([0, 0.4, 0], 0.5, box.center, box.half, box.axes))
  assert.ok(near(contact.depth, 0.1))
  assert.ok(near(contact.normal[1], 1) && near(contact.normal[0], 0) && near(contact.normal[2], 0))
})

test("a sphere whose centre is inside a box leaves by the nearest face", () => {
  const box = pad([0, 0, 0], 2, 2)
  const contact = touching(sphereBoxContact([0, -0.1, 0], 0.5, box.center, box.half, box.axes))
  assert.deepEqual(contact.normal, [0, 1, 0])
  assert.ok(near(contact.depth, 0.6))
})

test("a dropped ball bounces, then comes to rest on the floor", () => {
  const floor = [pad([0, 0, 0], 5, 5)]
  let ball = restingBall([0, 3, 0])
  let hardest = 0

  for (let i = 0; i < 600; i++) {
    const result = stepBall(ball, floor, i * DT, [0, -GRAVITY, 0], DT)
    ball = result.ball
    hardest = Math.max(hardest, result.impact)
  }

  assert.ok(hardest > 5, "it hit the floor")
  assert.ok(near(ball.position[1], BALL_RADIUS, 1e-3))
  assert.ok(length(ball.velocity) < 0.05)
})

test("a ball on a slope rolls without slipping at 5/7 of g·sin(θ)", () => {
  const floor = [pad([0, 0, 0], 200, 200)]
  const theta = 0.3
  const gravity: Vec3 = [Math.sin(theta) * GRAVITY, -Math.cos(theta) * GRAVITY, 0]
  let ball = restingBall([0, BALL_RADIUS, 0])

  const dt = 1 / 240
  const seconds = 1
  for (let i = 0; i < seconds / dt; i++) ball = stepBall(ball, floor, 0, gravity, dt).ball

  // rolling drag takes a little off the ideal figure
  const ideal = (5 / 7) * GRAVITY * Math.sin(theta) * seconds
  assert.ok(ball.velocity[0] > ideal * 0.85 && ball.velocity[0] <= ideal, `${ball.velocity[0]} vs ${ideal}`)

  // surface speed at the contact matches the floor: v = ω × r
  assert.ok(near(ball.velocity[0], -ball.angularVelocity[2] * BALL_RADIUS, 1e-3))
})

test("a ball rolling across the seam between two flush boxes is not kicked", () => {
  const floor = [pad([0, 0, 0], 2, 2), pad([4, 0, 0], 2, 2)]
  let ball: Ball = {...restingBall([0, BALL_RADIUS, 0]), velocity: [4, 0, 0], angularVelocity: [0, 0, -8]}

  for (let i = 0; i < 60; i++) {
    ball = stepBall(ball, floor, 0, [0, -GRAVITY, 0], DT).ball
    assert.ok(Math.abs(ball.position[1] - BALL_RADIUS) < 1e-3)
  }
  assert.ok(ball.position[0] > 3)
})

test("a ball at rest on a docked ferry is carried across with it", () => {
  // in dock at x = -3 at the start, at the far end x = 3 half a period later
  const ferry = mover([0, 0, 0], 2, 2, [3, 0, 0], 6, -Math.PI / 2)
  let ball = restingBall([-3, BALL_RADIUS, 0])

  for (let i = 1; i <= 180; i++) ball = stepBall(ball, [ferry], i * DT, [0, -GRAVITY, 0], DT).ball

  const {center} = colliderAt(ferry, 3)
  assert.ok(center[0] > 2.9, "the platform has travelled")
  assert.ok(Math.abs(ball.position[0] - center[0]) < 0.3, `and the ball went with it (${ball.position[0]})`)
})

test("a ball set down on a ferry in full flight is soon going its speed", () => {
  const ferry = mover([0, 0, 0], 8, 2, [3, 0, 0], 12)
  let ball = restingBall([0, BALL_RADIUS, 0])
  const start = colliderAt(ferry, 0).velocity[0]
  assert.ok(start > 2, "the ferry is moving")

  for (let i = 1; i <= 60; i++) ball = stepBall(ball, [ferry], i * DT, [0, -GRAVITY, 0], DT).ball

  const lag = colliderAt(ferry, 1).velocity[0] - ball.velocity[0]
  assert.ok(Math.abs(lag) < 0.15 * start, `${lag.toFixed(2)} behind after a second`)
})

test("a moving platform's reported velocity is the rate of change of its position", () => {
  const ferry = mover([0, 0, 0], 2, 2, [3, 1, 0], 6, 0.4)
  const h = 1e-5
  for (const t of [0, 0.7, 1.3, 2.9, 4.4, 5.5]) {
    const a = colliderAt(ferry, t - h).center
    const b = colliderAt(ferry, t + h).center
    const {velocity} = colliderAt(ferry, t)
    assert.ok(length(sub(scale(sub(b, a), 1 / (2 * h)), velocity)) < 1e-3, `at ${t}`)
  }
})

test("a ramp's top surface passes through both of its ends", () => {
  const ramp = slab([0, 0, 0], [0, -2, -8], 4)
  const ends: readonly Vec3[] = [[0, 0, 0], [0, -2, -8]]
  for (const end of ends) {
    const local = sub(end, ramp.center)
    assert.ok(near(dot(local, ramp.axes[1]), ramp.half[1]))
  }
  assert.ok(ramp.axes[1][1] > 0, "and faces up")
})

test("a turning platform's surface moves at ω × r: a point fixed on it moves exactly that fast", () => {
  const disc = rotor([2, 1, -3], 4, 4, 0.7, 0.3)
  const local: Vec3 = [2.5, 0.3, -1.5]
  const at = (t: number): Vec3 => {
    const {center, axes} = colliderAt(disc, t)
    return add(center, add(add(scale(axes[0], local[0]), scale(axes[1], local[1])), scale(axes[2], local[2])))
  }
  const h = 1e-5
  for (const t of [0, 1.1, 2.6, 7.3]) {
    const numeric = scale(sub(at(t + h), at(t - h)), 1 / (2 * h))
    const reported = surfaceVelocityAt(colliderAt(disc, t), at(t))
    assert.ok(length(sub(numeric, reported)) < 1e-4, `at ${t}`)
  }
})

test("a ball at rest on a turntable is carried round with it", () => {
  const rate = 0.5
  const disc = rotor([0, 0, 0], 5, 5, rate)
  let ball = restingBall([3, BALL_RADIUS, 0])

  // a quarter turn: from +x round to -z, counter-clockwise seen from above
  const steps = Math.round(Math.PI / 2 / rate / DT)
  for (let i = 1; i <= steps; i++) ball = stepBall(ball, [disc], i * DT, [0, -GRAVITY, 0], DT).ball

  const [x, , z] = ball.position
  const swept = Math.atan2(-z, x)
  assert.ok(swept > 1.1 && swept < Math.PI / 2 + 0.1, `swept ${swept.toFixed(2)} of ${(Math.PI / 2).toFixed(2)}`)
  assert.ok(Math.abs(Math.hypot(x, z) - 3) < 0.6, `and stayed about as far out (${Math.hypot(x, z).toFixed(2)})`)
})

test("a ball already going round with a turntable stays on its circle", () => {
  const rate = 0.6
  const disc = rotor([0, 0, 0], 5, 5, rate)
  // moving with the surface under it: ω × r for r = 3 along x
  let ball: Ball = {...restingBall([3, BALL_RADIUS, 0]), velocity: [0, 0, -3 * rate]}

  const steps = Math.round((2 * Math.PI) / rate / DT)
  for (let i = 1; i <= steps; i++) {
    ball = stepBall(ball, [disc], i * DT, [0, -GRAVITY, 0], DT).ball
    assert.ok(Math.abs(Math.hypot(ball.position[0], ball.position[2]) - 3) < 0.15, `step ${i}`)
  }
  assert.ok(length(sub(ball.position, [3, BALL_RADIUS, 0])) < 0.5, "and comes back round to where it began")
})

test("a bumper throws the ball straight back across the page, and says so", () => {
  const post = bumper([0, 0, -3])
  const world = [pad([0, 0, 0], 6, 6), post]
  // rolling, not sliding, toward it
  let ball: Ball = {...restingBall([0, BALL_RADIUS, 0]), velocity: [0, 0, -2], angularVelocity: [-4, 0, 0]}
  const hits: number[] = []

  for (let i = 1; i <= 120; i++) {
    const result = stepBall(ball, world, i * DT, [0, -GRAVITY, 0], DT)
    ball = result.ball
    hits.push(...result.bumped)
  }

  assert.deepEqual(hits, [1], "one kick, from the bumper at index 1")
  assert.ok(ball.velocity[2] > 0, "going back the way it came")
  assert.ok(ball.position[2] > 1, "and well away from the post")
  assert.ok(Math.abs(ball.position[1] - BALL_RADIUS) < 0.05, "without being thrown into the air")
})

test("a bumper's kick does not depend on how gently it was touched", () => {
  const post = bumper([0, 0, -3], 0.5, 7)
  const world = [pad([0, 0, 0], 6, 6), post]
  const outSpeed = (approach: number): number => {
    let ball: Ball = {...restingBall([0, BALL_RADIUS, -1.9]), velocity: [0, 0, -approach]}
    for (let i = 1; i <= 30; i++) {
      const result = stepBall(ball, world, i * DT, [0, -GRAVITY, 0], DT)
      ball = result.ball
      if (result.bumped.length > 0) return ball.velocity[2]
    }
    return 0
  }
  for (const approach of [0.5, 2, 6]) assert.ok(near(outSpeed(approach), 7, 0.05), `from ${approach} m/s`)
})

test("at top speed the ball cannot pass through a 0.6-thick floor or wall, whatever the step", () => {
  const floor = pad([0, 0, 0], 4, 4)
  const kerb = wall([0, 0, 0], 4, 0.3, 3)

  for (const dt of [1 / 240, 1 / 120, 1 / 60, 1 / 30, 1 / 10]) {
    // without cutting the step up, this one would carry the ball right through
    if (MAX_SPEED * dt > 1.1) {
      const diving: Ball = {...restingBall([0, 2, 0]), velocity: [0, -MAX_SPEED, 0]}
      assert.ok(splitsFor(diving, [floor], 0, [0, -GRAVITY, 0], dt) > 1, `dt ${dt} is split`)
    }
    for (let k = 0; k < 40; k++) {
      // every phase of the step relative to the surface
      const offset = (k / 40) * MAX_SPEED * dt

      const falling: Ball = {...restingBall([0, BALL_RADIUS + 0.01 + offset, 0]), velocity: [0, -MAX_SPEED, 0]}
      const down = stepBall(falling, [floor], 0, [0, -GRAVITY, 0], dt).ball
      assert.ok(down.position[1] > 0, `floor, dt ${dt}, offset ${offset.toFixed(3)}: ${down.position[1]}`)

      const rolling: Ball = {...restingBall([0, 1.5, 0.3 + BALL_RADIUS + 0.01 + offset]), velocity: [0, 0, -MAX_SPEED]}
      const through = stepBall(rolling, [kerb], 0, [0, 0, 0], dt).ball
      assert.ok(through.position[2] > 0, `wall, dt ${dt}, offset ${offset.toFixed(3)}: ${through.position[2]}`)
    }
  }
})

// --- rules -----------------------------------------------------------------

test("leaning the stage swings gravity without changing its strength", () => {
  assert.deepEqual(gravityFor([0, 0, 0]), [0, -GRAVITY, 0])
  const g = gravityFor([1, 0, 0])
  assert.ok(near(length(g), GRAVITY))
  assert.ok(near(Math.atan2(g[0], -g[1]), MAX_TILT))
})

test("a stage opens in `ready`, drops the ball, then lets the player go", () => {
  let state = newGame()
  assert.equal(state.phase, "ready")

  state = run(state, {x: 1, y: 0}, 1)
  assert.equal(state.phase, "ready")
  assert.ok(Math.abs(state.ball.position[0]) < 1e-6, "input is ignored until go")

  state = run(state, {x: 0, y: 0}, 0.6)
  assert.equal(state.phase, "playing")
  assert.ok(near(state.ball.position[1], BALL_RADIUS, 0.02))
})

test("pushing the stick away rolls the ball away from the camera", () => {
  const state = run(newGame(), {x: 0, y: 1}, 2.5)
  assert.ok(state.ball.position[2] < -1)
  assert.ok(Math.abs(state.ball.position[0]) < 0.01)
})

test("rolling off the edge is a fallout and starts the stage again", () => {
  let state = run(newGame(), {x: 1, y: 0}, 1.5)
  const seen = new Set<GameEventType>()

  for (let i = 0; i < 600 && state.attempts === 1; i++) {
    state = step(state, {x: 1, y: 0}, DT)
    state.events.forEach(e => seen.add(e.type))
  }

  assert.ok(seen.has("fallout"))
  assert.equal(state.attempts, 2)
  assert.equal(state.phase, "ready")
  assert.equal(state.gems, 0)
})

test("the clock running out ends the attempt", () => {
  const levels: readonly Level[] = [{...levelAt(0), time: 2}]
  let state = run(startLevel(0, 0, levels), {x: 0, y: 0}, 3.6, levels)
  assert.equal(state.phase, "timeup")
  state = run(state, {x: 0, y: 0}, 2, levels)
  assert.equal(state.attempts, 2)
})

test("the same inputs always give the same run", () => {
  const play = (): GameState => run(run(newGame(), {x: 0.3, y: 1}, 3), {x: -0.6, y: 0.2}, 2)
  assert.deepEqual(play(), play())
})

test("step does not modify the state it is given", () => {
  const state = run(newGame(), {x: 0, y: 1}, 2)
  const before = JSON.stringify(state)
  step(state, {x: 1, y: 1}, DT)
  assert.equal(JSON.stringify(state), before)
})

test("particles and the seed are carried through a step", () => {
  const state = run(newGame(), {x: 0, y: 1}, 2)
  const next = step(state, {x: 0, y: 1}, DT)
  assert.deepEqual(next.particles, [])
  assert.equal(next.seed, state.seed)
  assert.equal(restart(state).seed, state.seed, "a retry keeps its place in the random sequence")
  assert.notEqual(startLevel(0).seed, startLevel(1).seed, "each stage has its own")
})

test("a finishing time earns the best medal whose par it beats", () => {
  const level = levelAt(0)
  const {gold, silver, bronze} = level.par
  assert.ok(gold > 0 && gold < silver && silver < bronze && bronze < level.time)

  assert.equal(medalFor(level, gold - 1), "gold")
  assert.equal(medalFor(level, gold), "gold")
  assert.equal(medalFor(level, gold + 0.01), "silver")
  assert.equal(medalFor(level, silver), "silver")
  assert.equal(medalFor(level, bronze), "bronze")
  assert.equal(medalFor(level, bronze + 0.01), null)
})

test("medals for every stage follow its par exactly", () => {
  for (const level of LEVELS) {
    const {gold, silver, bronze} = level.par
    assert.equal(medalFor(level, 0.5), "gold", level.name)
    assert.equal(medalFor(level, gold), "gold", level.name)
    assert.equal(medalFor(level, gold + 1e-9), "silver", level.name)
    assert.equal(medalFor(level, silver), "silver", level.name)
    assert.equal(medalFor(level, silver + 1e-9), "bronze", level.name)
    assert.equal(medalFor(level, bronze), "bronze", level.name)
    assert.equal(medalFor(level, bronze + 1e-9), null, level.name)
    assert.equal(medalFor(level, level.time), null, level.name)
  }
})

test("the page leans with the stick at the end of the countdown, but the ball and the clock wait for go", () => {
  const level = levelAt(0)
  let state = run(newGame(), {x: 0, y: 0}, READY_TIME - LAUNCH_GRACE - 0.05)
  assert.deepEqual(state.tilt, [0, 0, 0], "no lean before the grace")

  for (let i = 0; i < 400 && state.phase === "ready"; i++) state = step(state, {x: 0, y: 1}, DT)
  assert.equal(state.phase, "playing")
  assert.ok(state.tilt[2] < -0.9, `leaning forward already at go (${state.tilt[2].toFixed(2)})`)
  assert.ok(Math.abs(state.ball.position[2] - level.start[2]) < 1e-3, "the ball was held")
  assert.ok(near(state.timeLeft, level.time), "and the clock has not started")

  const later = run(state, {x: 0, y: 1}, 1)
  assert.ok(near(later.timeLeft, level.time - 1, 1e-6), "it runs from go")
})

test("the state carries the ball's speed across the page", () => {
  const state = run(newGame(), {x: 0.4, y: 1}, 3)
  assert.ok(state.speed > 1)
  assert.ok(near(state.speed, Math.hypot(state.ball.velocity[0], state.ball.velocity[2])))
})

// A small test stage: a pad with gems in a row ahead of the start.
const strip = (gems: readonly Vec3[], extra: readonly Platform[] = []): readonly Level[] => [
  {...levelAt(0), start: [0, 0, 0], platforms: [pad([0, 0, -10], 4, 12), ...extra], gems},
]

test("collecting every gem marks the run perfect; missing one does not", () => {
  const all = strip([[0, 0, -3], [0, 0, -6]])
  const done = run(startLevel(0, 0, all), {x: 0, y: 1}, 4, all)
  assert.equal(done.gems, 2)
  assert.equal(done.perfect, true)

  const missed = strip([[0, 0, -3], [3, 0, -6]])
  const partial = run(startLevel(0, 0, missed), {x: 0, y: 1}, 4, missed)
  assert.equal(partial.gems, 1)
  assert.equal(partial.perfect, false)
  assert.equal(startLevel(0, 0, all).perfect, false, "and a fresh stage is not")
})

test("picking up a gem throws sparks that replay exactly, fall, and die", () => {
  const levels = strip([[0, 0, -3]])
  const until = (): GameState => {
    let state = startLevel(0, 0, levels)
    for (let i = 0; i < 600 && state.gems === 0; i++) state = step(state, {x: 0, y: 1}, DT, levels)
    return state
  }

  const a = until()
  const b = until()
  assert.equal(a.gems, 1)
  assert.ok(a.particles.length > 0, "sparks")
  assert.deepEqual(a, b, "the same inputs throw the same sparks")
  assert.notEqual(a.seed, startLevel(0, 0, levels).seed, "the PRNG moved on")

  const later = step(a, {x: 0, y: 0}, DT, levels)
  for (const [i, p] of later.particles.entries()) {
    const before = a.particles[i]
    assert.ok(before, "the same specks")
    assert.ok(p.life < before.life, "aged")
  }

  const gone = run(a, {x: 0, y: 0}, 2, levels)
  assert.deepEqual(gone.particles, [], "and all spent after a couple of seconds")
})

test("sparks stay within bounds however many gems go at once", () => {
  const pile = Array.from({length: 30}, (): Vec3 => [0, 0, -3])
  const levels = strip(pile)
  let state = startLevel(0, 0, levels)
  for (let i = 0; i < 600 && state.gems === 0; i++) state = step(state, {x: 0, y: 1}, DT, levels)
  assert.equal(state.gems, 30)
  assert.equal(state.particles.length, MAX_PARTICLES)
})

test("reaching the goal throws confetti", () => {
  const level = levelAt(0)
  const atGoal: GameState = {
    ...startLevel(0),
    phase: "playing",
    ball: {...startLevel(0).ball, position: goalCenter(level)},
  }
  const next = step(atGoal, {x: 0, y: 0}, DT)
  assert.equal(next.phase, "goal")
  assert.ok(next.particles.length >= 30)
  assert.ok(next.particles.every(p => p.life > 0 && p.life <= p.maxLife))
})

test("a ball driven into the ring at full stick stays on the page through the celebration", () => {
  const level = levelAt(0)
  const base = startLevel(0)
  const from: Vec3 = [4.5, BALL_RADIUS, -24]
  // facing +x, the way the ring lies from here, so full stick runs straight at it
  let state: GameState = {...base, phase: "playing", ball: {...base.ball, position: from}, camera: {yaw: -Math.PI / 2, focus: from}}
  let entry = 0
  for (let i = 0; i < 900 && state.phase !== "cleared"; i++) {
    const was = state.phase
    state = step(state, {x: 0, y: 1}, DT)
    if (was === "playing" && state.phase === "goal") entry = state.speed
    assert.notEqual(state.phase, "fallout")
  }
  assert.equal(state.phase, "cleared")
  assert.ok(entry > 9, `entered the ring at only ${entry.toFixed(1)} m/s`)
  assert.ok(near(state.ball.position[1], goalCenter(level)[1], 0.05), `ball at y ${state.ball.position[1].toFixed(2)}`)
  assert.ok(length(sub(state.ball.position, goalCenter(level))) < 0.5, "the ring holds the ball near its centre")
})

test("on every stage the ring catches a ball arriving at top speed from any side", () => {
  LEVELS.forEach((level, index) => {
    for (const heading of [0, Math.PI / 2, Math.PI, -Math.PI / 2]) {
      const base = startLevel(index)
      const center = goalCenter(level)
      const velocity: Vec3 = [Math.cos(heading) * 16, 0, Math.sin(heading) * 16]
      let state: GameState = {...base, phase: "goal", ball: {...base.ball, position: center, velocity}, camera: {yaw: 0, focus: center}}
      while (state.phase === "goal") state = step(state, {x: 0, y: 0}, DT)
      const where = state.ball.position.map(n => n.toFixed(2)).join(",")
      assert.ok(near(state.ball.position[1], center[1], 0.05), `${level.name}, heading ${heading.toFixed(2)}: ball at ${where}`)
      assert.ok(near(state.camera.focus[1], center[1], 0.2), `${level.name}: the camera stayed with the page`)
    }
  })
})

test("the camera stops following a ball that has dropped below the page", () => {
  const level = levelAt(0)
  const base = startLevel(0)
  const below: Vec3 = [0, killHeight(level) + 2, -50]
  const state: GameState = {...base, phase: "goal", ball: {...base.ball, position: below, velocity: [0, -5, 0]}}
  const next = step(state, {x: 0, y: 0}, DT)
  assert.deepEqual(next.camera, state.camera)
})

test("hitting a bumper during play is reported with its index, with a few sparks", () => {
  const levels = strip([], [bumper([0, 0, -4])])
  let state = startLevel(0, 0, levels)
  const seen: GameEvent[] = []
  for (let i = 0; i < 400 && seen.length === 0; i++) {
    state = step(state, {x: 0, y: 1}, DT, levels)
    seen.push(...state.events.filter(e => e.type === "bumper"))
  }
  assert.deepEqual(seen, [{type: "bumper", index: 1}])
  assert.ok(state.particles.length > 0)
  assert.ok(!state.events.some(e => e.type === "bounce"), "a kick is not also a thud")
})

test("every stage has par times that tighten toward gold and fit on its clock", () => {
  assert.equal(levelCount(), LEVELS.length)
  for (const level of LEVELS) {
    const {gold, silver, bronze} = level.par
    assert.ok(gold > 0 && gold < silver && silver < bronze && bronze < level.time, level.name)
  }
})

// --- stages ----------------------------------------------------------------

test("every stage starts over solid ground with its gems and goal within reach of a surface", () => {
  for (const level of LEVELS) {
    const supported = (point: Vec3): boolean =>
      level.platforms.some(p => {
        // anywhere along a moving platform's travel, or a turning one's
        // sweep, counts; a bumper is never somewhere to stand
        if (p.kind === "bumper") return false
        const period = p.kind === "mover" ? p.motion.period : p.kind === "rotor" ? (2 * Math.PI) / Math.abs(p.spin.rate) : 1
        return Array.from({length: 16}, (_, i) => i / 16).some(f => {
          const {center, axes} = colliderAt(p, period * f)
          const c = sphereBoxContact(add(point, [0, 0.3, 0]), 0.6, center, p.half, axes)
          return c !== null && c.normal[1] > 0.5
        })
      })

    assert.ok(supported(level.start), `${level.name}: start`)
    assert.ok(supported(level.goal.position), `${level.name}: goal`)
    level.gems.forEach((gem, i) => assert.ok(supported(gem), `${level.name}: gem ${i}`))
    assert.ok(killHeight(level) < Math.min(...level.gems.map(g => g[1])) - 5)
  }
})

// A scripted player: steer toward each waypoint in turn, slowing near it.
// A waypoint may be a function of the state, for standing on things that move.
interface Aim {
  readonly at: Vec3
  // how close counts as arrived
  readonly within?: number
  // and what else must be true before moving on
  readonly until?: () => boolean
  readonly speed?: number
  // how fast the target itself is moving, to keep up with it
  readonly drift?: Vec3
}

type Waypoint = Vec3 | ((state: GameState) => Aim)

interface Run {
  readonly state: GameState
  readonly events: readonly GameEventType[]
}

const autopilot = (levelIndex: number, waypoints: readonly Waypoint[], banked = 0): Run => {
  let state = startLevel(levelIndex, banked)
  let target = 0
  const events: GameEventType[] = []
  const limit = (levelAt(levelIndex).time + READY_TIME + GOAL_TIME + 1) / DT

  for (let i = 0; i < limit && state.phase !== "cleared"; i++) {
    let input: Input = {x: 0, y: 0}

    if (state.phase === "playing") {
      const waypoint = waypoints[Math.min(target, waypoints.length - 1)]
      assert.ok(waypoint, "the route has waypoints")
      const spec: Aim = typeof waypoint === "function" ? waypoint(state) : {at: waypoint}
      const to = sub(spec.at, state.ball.position)
      const flat: Vec3 = [to[0], 0, to[2]]
      const gap = length(flat)

      if (gap < (spec.within ?? 1) && (!spec.until || spec.until()) && target < waypoints.length - 1) {
        target++
      }

      const cruise = spec.speed ?? 6
      const wanted = add(scale(normalize(flat), Math.min(cruise, gap * 2.5)), spec.drift ?? [0, 0, 0])
      const push = scale(sub(wanted, [state.ball.velocity[0], 0, state.ball.velocity[2]]), 0.6)
      input = {x: dot(push, rightFromYaw(state.camera.yaw)), y: dot(push, forwardFromYaw(state.camera.yaw))}
    }

    const before = state
    state = step(state, input, DT)
    events.push(...state.events.map(e => e.type))

    const lost = state.events.find(e => e.type === "fallout" || e.type === "timeup")
    if (lost) {
      const where = before.ball.position.map(n => n.toFixed(1))
      assert.fail(`${lost.type} at ${where.join(",")}, heading for waypoint ${target}, clock ${state.clock.toFixed(1)}`)
    }
  }

  assert.equal(state.phase, "cleared", `stage ${levelIndex + 1} not finished: ${state.phase}, waypoint ${target}`)
  return {state, events}
}

const platformTop = (level: Level, index: number) => (state: GameState): Vec3 => {
  const p = platform(level, index)
  return add(colliderAt(p, state.clock).center, [0, p.half[1], 0])
}

test("stage 1 can be finished, picking up gems on the way", () => {
  const {state, events} = autopilot(0, [[0, 0, -9], [0, 0, -23], [9, 0, -24], goalCenter(levelAt(0))])
  assert.equal(state.phase, "cleared")
  assert.ok(events.includes("goal"))
  assert.ok(state.gems >= 5, `${state.gems} gems`)
  assert.notEqual(medalFor(levelAt(0), elapsed(state)), null, `a medal for ${elapsed(state).toFixed(1)}s`)
})

test("stage 2 can be finished", () => {
  const route: readonly Vec3[] = [
    [0, -2, -14],
    [16, -2, -14],
    [16, -2, -30],
    [12, -2, -30],
    goalCenter(levelAt(1)),
  ]
  const {state} = autopilot(1, route.map(at => () => ({at, speed: 4.5, within: 0.8})))
  assert.equal(state.phase, "cleared")
  assert.ok(state.timeLeft > 0)
  assert.notEqual(medalFor(levelAt(1), elapsed(state)), null, `a medal for ${elapsed(state).toFixed(1)}s`)
})

test("stage 3 can be finished by riding both moving platforms", () => {
  const level = levelAt(2)
  const ferry = platformTop(level, 2)
  const lift = platformTop(level, 6)

  const {state} = autopilot(2, [
    // wait at the lip until the ferry is in dock
    s => ({at: [0, 0, -8], within: 0.6, until: () => ferry(s)[2] > -11.3}),
    // ride it across
    s => ({at: add(ferry(s), [0, 0, -1.2]), within: 0.9, until: () => ferry(s)[2] < -20.9}),
    () => ({at: [0, 0, -26]}),
    () => ({at: [-12, 0, -26], speed: 4.5}),
    // wait for the lift at the bottom, ride it to the top
    s => ({at: [-12, 0, -27.8], within: 0.6, until: () => lift(s)[1] < 0.12}),
    s => ({at: lift(s), within: 0.9, until: () => lift(s)[1] > 2.9}),
    () => ({at: goalCenter(level)}),
  ])

  assert.equal(state.phase, "cleared")
  assert.notEqual(medalFor(level, elapsed(state)), null, `a medal for ${elapsed(state).toFixed(1)}s`)
})

// Where a turning platform's arms point. `symmetry` is the turn after which
// it looks the same again: π for a bar, π/2 for a plus-shaped turntable.
interface Arms {
  readonly hub: (state: GameState) => Vec3
  // how far the arm nearest `direction` is from pointing along it, in
  // radians; negative while it is still on its way there
  readonly behind: (state: GameState) => number
  // the far end of that arm, a little in from the edge
  readonly tip: (state: GameState) => Vec3
  readonly drift: (state: GameState) => Vec3
}

const arms = (level: Level, index: number, direction: Vec3, symmetry: number): Arms => {
  const p = platform(level, index)
  assert.ok(p.kind === "rotor", `${level.name}: platform ${index} turns`)
  const wanted = Math.atan2(direction[0], direction[2])
  const offset = (state: GameState): number => {
    const angle = p.spin.phase + p.spin.rate * state.clock
    return ((((angle - wanted) % symmetry) + symmetry * 1.5) % symmetry) - symmetry / 2
  }
  const top = (state: GameState): Vec3 => add(colliderAt(p, state.clock).center, [0, p.half[1], 0])
  return {
    hub: top,
    behind: state => offset(state) * Math.sign(p.spin.rate),
    tip: state => {
      const angle = wanted + offset(state)
      return add(top(state), scale([Math.sin(angle), 0, Math.cos(angle)], p.half[2] - 0.9))
    },
    // only once aboard: off the end, the turn is not the ball's to follow
    drift: state => {
      const placement = colliderAt(p, state.clock)
      const off = sub(state.ball.position, placement.center)
      return Math.hypot(off[0], off[2]) < p.half[2] ? surfaceVelocityAt(placement, state.ball.position) : [0, 0, 0]
    },
  }
}

// Wait at `at` for the arm to come round, stepping off just before it is in
// line so it has arrived by the time the ball crosses the gap.
const waitForArm = (at: Vec3, arm: Arms): Waypoint => s => ({
  at,
  within: 0.6,
  until: () => arm.behind(s) > -0.3 && arm.behind(s) < -0.08,
})

// Run in along the arm to the hub, keeping up with it as it swings, and hold
// there until the way-out arm is far enough round that riding it out takes
// the ball to the end just as it comes into line.
const toHub = (arm: Arms, out: Arms, leaveAt: number): Waypoint => s => ({
  at: arm.hub(s),
  within: 0.45,
  speed: 5,
  drift: arm.drift(s),
  until: () => out.behind(s) > leaveAt && out.behind(s) < leaveAt + 0.15,
})

// Ride out along the arm, and wait at its end until it is in line.
const toTip = (arm: Arms): Waypoint => s => ({
  at: arm.tip(s),
  within: 0.7,
  speed: 4,
  drift: arm.drift(s),
  until: () => arm.behind(s) > -0.06 && arm.behind(s) < 0.04,
})

test("stage 4 can be finished by riding both turntables to their hubs", () => {
  const level = levelAt(3)
  const plusIn = arms(level, 2, [0, 0, 1], Math.PI / 2)
  const plusOut = arms(level, 2, [1, 0, 0], Math.PI / 2)
  const barIn = arms(level, 7, [0, 0, 1], Math.PI)
  const barOut = arms(level, 7, [0, 0, -1], Math.PI)

  const {state} = autopilot(3, [
    () => ({at: [0, 0, -6], speed: 5}),
    waitForArm([0, 0, -8.7], plusIn),
    toHub(plusIn, plusOut, -0.9),
    toTip(plusOut),
    () => ({at: [9, 0, -16], speed: 4}),
    () => ({at: [15, 0, -16], speed: 4}),
    waitForArm([15, 0, -18.8], barIn),
    toHub(barIn, barOut, -1),
    toTip(barOut),
    () => ({at: [15, 0, -33], speed: 4}),
    () => ({at: goalCenter(level), speed: 4}),
  ])

  assert.notEqual(medalFor(level, elapsed(state)), null, `a medal for ${elapsed(state).toFixed(1)}s`)
})

test("stage 5 can be finished without touching a bumper", () => {
  const level = levelAt(4)
  const route: readonly Vec3[] = [
    [0, 0, -5],
    [-0.85, 0, -8],
    [0.85, 0, -12],
    [-0.85, 0, -16],
    [0.85, 0, -20],
    [-0.85, 0, -24],
    [0, 0, -28.5],
    [-3.5, 0, -30.4],
    [-6.5, 0, -31.3],
    [-10, 0, -29.3],
    [-13.5, 0, -31.3],
    [-17, 0, -30],
    goalCenter(level),
  ]
  const {state, events} = autopilot(4, route.map(at => () => ({at, speed: 3.4, within: 0.5})))

  assert.ok(!events.includes("bumper"), "clean through the gaps")
  assert.notEqual(medalFor(level, elapsed(state)), null, `a medal for ${elapsed(state).toFixed(1)}s`)
})

test("stage 6 can be finished: ramp, ferry, turning bar, climb", () => {
  const level = levelAt(5)
  const ferry = platformTop(level, 3)
  const barIn = arms(level, 6, [-1, 0, 0], Math.PI)
  const barOut = arms(level, 6, [0, 0, -1], Math.PI)

  const {state} = autopilot(5, [
    () => ({at: [0, 0, -13], speed: 4}),
    s => ({at: [0, 0, -16.2], within: 0.6, until: () => ferry(s)[2] > -19.3}),
    s => ({at: add(ferry(s), [0, 0, -1.2]), within: 0.9, until: () => ferry(s)[2] < -28.9}),
    () => ({at: [0, 0, -34]}),
    () => ({at: [5, 0.33, -34], speed: 4}),
    waitForArm([8.2, 0.87, -34], barIn),
    toHub(barIn, barOut, -1),
    toTip(barOut),
    () => ({at: [15.3, 1, -42], speed: 4}),
    () => ({at: [15.3, 3, -49], speed: 5}),
    () => ({at: goalCenter(level), speed: 4}),
  ])

  assert.notEqual(medalFor(level, elapsed(state)), null, `a medal for ${elapsed(state).toFixed(1)}s`)
})

test("clearing a stage banks its gems and moves on; clearing the last starts over", () => {
  const cleared: GameState = {...startLevel(0), phase: "cleared", gems: 3}
  const next = advance(cleared)
  assert.equal(next.levelIndex, 1)
  assert.equal(next.banked, 3)

  const last: GameState = {...startLevel(LEVELS.length - 1, 9), phase: "cleared"}
  assert.equal(advance(last).levelIndex, 0)
  assert.equal(advance(startLevel(0)).levelIndex, 0, "only a cleared stage advances")
})

// --- picture ---------------------------------------------------------------

test("meshes are well formed", () => {
  for (const [name, mesh] of Object.entries(buildMeshes())) {
    const count = mesh.positions.length / 3
    assert.equal(mesh.normals.length, mesh.positions.length, name)
    assert.equal(mesh.smooth.length, mesh.positions.length, name)
    assert.equal(mesh.indices.length % 3, 0, name)
    assert.ok(Math.max(...mesh.indices) < count, name)
  }
})

test("the scene lists every platform, uncollected gem, the goal and the ball, with the ball on screen", () => {
  const level = levelAt(0)
  const state = run(newGame(), {x: 0, y: 1}, 3.5)
  assert.ok(state.gems >= 1)

  const scene = buildScene(state, 9 / 16)
  const count = (mesh: string): number => scene.items.filter(i => i.mesh === mesh).length

  assert.equal(count("sphere"), 1)
  assert.equal(count("torus"), 1)
  assert.equal(count("gem"), level.gems.length - state.gems)
  assert.equal(count("box"), level.platforms.length + 1)

  const [x, y] = mat4TransformPoint(scene.viewProjection, state.ball.position)
  assert.ok(Math.abs(x) < 0.5 && Math.abs(y) < 0.7, `ball at ${x}, ${y}`)
})

test("only things that stand up off the page cast shadows, and the scene carries the clock", () => {
  const state = run(newGame(), {x: 0, y: 1}, 1)
  const scene = buildScene(state, 16 / 9)
  const casters = scene.items.filter(i => i.castsShadow).map(i => i.mesh)

  assert.ok(casters.includes("sphere") && casters.includes("torus") && casters.includes("gem"))
  // stage 1's two walls cast; its two floors and the painted goal line do not
  assert.equal(casters.filter(m => m === "box").length, 2)
  assert.equal(scene.time, state.clock)
  assert.deepEqual(scene.particles, [])
})

test("the camera stays above the leaned stage, even looking back up a ramp at full tilt", () => {
  // stage 2, on the landing at the foot of the downhill ramp, stick hard forward
  const base = startLevel(1)
  const position: Vec3 = [0, -2 + BALL_RADIUS, -12]
  const state: GameState = {
    ...base,
    phase: "playing",
    tilt: [0, 0, -1],
    ball: {...base.ball, position},
    camera: {yaw: 0, focus: position},
  }

  for (const aspect of [9 / 19.5, 16 / 9]) {
    const scene = buildScene(state, aspect)
    // The ramp's top face, under the camera: it must be in front of the lens
    // and below the middle of the picture, i.e. seen from above.
    const ramp = platform(levelAt(1), 1)
    const under = add(ramp.center, scale(ramp.axes[1], ramp.half[1]))
    const [, y, z] = mat4TransformPoint(scene.viewProjection, under)
    assert.ok(z < 1 && y < -0.2, `aspect ${aspect.toFixed(2)}: ramp at y ${y.toFixed(2)}`)
  }
})

test("on every ramp of every stage, the camera stays above the slope going down it at full tilt", () => {
  let ramps = 0
  LEVELS.forEach((level, index) => {
    level.platforms.forEach((p, i) => {
      if (p.kind !== "floor" || p.axes[1][1] > 0.999) return
      ramps++
      const normal = p.axes[1]
      const downhill = normalize([normal[0], 0, normal[2]])
      // the strip's long axis, pointing down the slope
      const along = p.axes[2][1] < 0 ? p.axes[2] : scale(p.axes[2], -1)
      const top = add(p.center, scale(normal, p.half[1]))
      const foot = add(top, scale(along, p.half[2]))
      const position = add(add(foot, scale(downhill, 1)), [0, BALL_RADIUS, 0])
      const base = startLevel(index)
      const state: GameState = {
        ...base,
        phase: "playing",
        tilt: downhill,
        ball: {...base.ball, position},
        camera: {yaw: Math.atan2(-downhill[0], -downhill[2]), focus: position},
      }

      for (const aspect of [9 / 19.5, 16 / 9]) {
        const m = buildScene(state, aspect).viewProjection
        // Every point up the middle of the slope that is in front of the
        // lens must sit below the middle of the picture: seen from above.
        for (let t = -p.half[2]; t <= p.half[2]; t += 0.5) {
          const point = add(top, scale(along, t))
          const w = m[3] * point[0] + m[7] * point[1] + m[11] * point[2] + m[15]
          if (w < 0.3) continue
          const [, y] = mat4TransformPoint(m, point)
          assert.ok(y < 0, `${level.name} ramp ${i}, aspect ${aspect.toFixed(2)}: slope at y ${y.toFixed(2)}`)
        }
      }
    })
  })
  assert.ok(ramps >= 3, `only ${ramps} ramps found`)
})

test("turntables are drawn where they have turned to, and bumpers as round posts", () => {
  const level = levelAt(3)
  const state: GameState = {...startLevel(3), clock: 2.3}
  const scene = buildScene(state, 9 / 16)

  level.platforms.forEach((p, i) => {
    const item = scene.items[i]
    assert.ok(item, `an item for platform ${i}`)
    const {center, axes} = colliderAt(p, state.clock)
    assert.deepEqual(item.model, mat4FromBasis(center, axes), `platform ${i} is where physics has it`)
    if (p.kind === "rotor") assert.ok(item.castsShadow)
  })
  // a painted hub on every turning bar, lying flat on its top face
  const hubs = scene.items.filter(i => i.mesh === "disc")
  assert.equal(hubs.length, level.platforms.filter(p => p.kind === "rotor").length)
  assert.ok(hubs.every(i => !i.castsShadow && i.outline === 0))

  const posts = levelAt(4).platforms.filter(p => p.kind === "bumper")
  const drawn = buildScene(startLevel(4), 16 / 9).items.filter(i => i.mesh === "sphere" && i.pattern === "plain")
  assert.equal(drawn.length, posts.length)
  assert.ok(drawn.every(i => i.castsShadow && (near(i.scale[0], 0.5) || near(i.scale[0], 0.4))))
})

test("the scene shows particles fading as they age", () => {
  const levels = strip([[0, 0, -3]])
  let state = startLevel(0, 0, levels)
  for (let i = 0; i < 600 && state.gems === 0; i++) state = step(state, {x: 0, y: 1}, DT, levels)
  state = run(state, {x: 0, y: 0}, 0.2, levels)

  const scene = buildScene(state, 1, levels)
  assert.equal(scene.particles.length, state.particles.length)
  assert.ok(scene.particles.every(p => p.alpha > 0 && p.alpha < 1))
})
