// Run with: node --test assets/test/game
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
  rightFromYaw,
  scale,
  sub,
} from "../../js/game/core/math.js"
import {BALL_RADIUS, colliderAt, sphereBoxContact, stepBall} from "../../js/game/core/physics.js"
import {LEVELS, killHeight, mover, pad, slab} from "../../js/game/core/levels.js"
import {
  GRAVITY,
  MAX_TILT,
  advance,
  goalCenter,
  gravityFor,
  newGame,
  startLevel,
  step,
} from "../../js/game/core/game.js"
import {buildMeshes} from "../../js/game/core/meshes.js"
import {buildScene} from "../../js/game/core/scene.js"

const DT = 1 / 60
const near = (a, b, eps = 1e-6) => Math.abs(a - b) < eps

const restingBall = position => ({
  position,
  velocity: [0, 0, 0],
  angularVelocity: [0, 0, 0],
  orientation: [0, 0, 0, 1],
})

const run = (state, input, seconds, levels) => {
  for (let i = 0; i < Math.round(seconds / DT); i++) state = step(state, input, DT, levels)
  return state
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

// --- physics ---------------------------------------------------------------

test("a sphere above a box does not touch it; one sunk into it is pushed up", () => {
  const box = pad([0, 0, 0], 2, 2)
  assert.equal(sphereBoxContact([0, 0.6, 0], 0.5, box.center, box.half, box.axes), null)

  const contact = sphereBoxContact([0, 0.4, 0], 0.5, box.center, box.half, box.axes)
  assert.ok(near(contact.depth, 0.1))
  assert.ok(near(contact.normal[1], 1) && near(contact.normal[0], 0) && near(contact.normal[2], 0))
})

test("a sphere whose centre is inside a box leaves by the nearest face", () => {
  const box = pad([0, 0, 0], 2, 2)
  const contact = sphereBoxContact([0, -0.1, 0], 0.5, box.center, box.half, box.axes)
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
  const gravity = [Math.sin(theta) * GRAVITY, -Math.cos(theta) * GRAVITY, 0]
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
  let ball = {...restingBall([0, BALL_RADIUS, 0]), velocity: [4, 0, 0], angularVelocity: [0, 0, -8]}

  for (let i = 0; i < 60; i++) {
    ball = stepBall(ball, floor, 0, [0, -GRAVITY, 0], DT).ball
    assert.ok(Math.abs(ball.position[1] - BALL_RADIUS) < 1e-3)
  }
  assert.ok(ball.position[0] > 3)
})

test("a ball at rest on a moving platform is carried along with it", () => {
  const platform = mover([0, 0, 0], 2, 2, [3, 0, 0], 6)
  let ball = restingBall([0, BALL_RADIUS, 0])

  for (let i = 1; i <= 90; i++) ball = stepBall(ball, [platform], i * DT, [0, -GRAVITY, 0], DT).ball

  const {center} = colliderAt(platform, 1.5)
  assert.ok(center[0] > 2.9, "the platform has travelled")
  assert.ok(Math.abs(ball.position[0] - center[0]) < 1, `and the ball went with it (${ball.position[0]})`)
})

test("a moving platform's reported velocity is the rate of change of its position", () => {
  const platform = mover([0, 0, 0], 2, 2, [3, 1, 0], 6, 0.4)
  const h = 1e-5
  for (const t of [0, 0.7, 1.3, 2.9, 4.4, 5.5]) {
    const a = colliderAt(platform, t - h).center
    const b = colliderAt(platform, t + h).center
    const {velocity} = colliderAt(platform, t)
    assert.ok(length(sub(scale(sub(b, a), 1 / (2 * h)), velocity)) < 1e-3, `at ${t}`)
  }
})

test("a ramp's top surface passes through both of its ends", () => {
  const ramp = slab([0, 0, 0], [0, -2, -8], 4)
  for (const end of [[0, 0, 0], [0, -2, -8]]) {
    const local = sub(end, ramp.center)
    assert.ok(near(dot(local, ramp.axes[1]), ramp.half[1]))
  }
  assert.ok(ramp.axes[1][1] > 0, "and faces up")
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
  const seen = new Set()

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
  const levels = [{...LEVELS[0], time: 2}]
  let state = run(startLevel(0, 0, levels), {x: 0, y: 0}, 3.6, levels)
  assert.equal(state.phase, "timeup")
  state = run(state, {x: 0, y: 0}, 2, levels)
  assert.equal(state.attempts, 2)
})

test("the same inputs always give the same run", () => {
  const play = () => run(run(newGame(), {x: 0.3, y: 1}, 3), {x: -0.6, y: 0.2}, 2)
  assert.deepEqual(play(), play())
})

test("step does not modify the state it is given", () => {
  const state = run(newGame(), {x: 0, y: 1}, 2)
  const before = JSON.stringify(state)
  step(state, {x: 1, y: 1}, DT)
  assert.equal(JSON.stringify(state), before)
})

// --- stages ----------------------------------------------------------------

test("every stage starts over solid ground with its gems and goal within reach of a surface", () => {
  for (const level of LEVELS) {
    const supported = point =>
      level.platforms.some(p => {
        // anywhere along a moving platform's travel counts
        return [0, 0.25, 0.5, 0.75].some(f => {
          const {center} = colliderAt(p, (p.motion?.period || 1) * f)
          const c = sphereBoxContact(add(point, [0, 0.3, 0]), 0.6, center, p.half, p.axes)
          return c && c.normal[1] > 0.5
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
const autopilot = (levelIndex, waypoints, banked = 0) => {
  let state = startLevel(levelIndex, banked)
  let target = 0
  const events = []

  for (let i = 0; i < 90 / DT && state.phase !== "cleared"; i++) {
    let input = {x: 0, y: 0}

    if (state.phase === "playing") {
      const waypoint = waypoints[Math.min(target, waypoints.length - 1)]
      const spec = typeof waypoint === "function" ? waypoint(state) : {at: waypoint}
      const to = sub(spec.at, state.ball.position)
      const flat = [to[0], 0, to[2]]
      const gap = length(flat)

      if (gap < (spec.within || 1) && (!spec.until || spec.until(state)) && target < waypoints.length - 1) {
        target++
      }

      const cruise = spec.speed || 6
      const wanted = scale(normalize(flat), Math.min(cruise, gap * 2.5))
      const push = scale(sub(wanted, [state.ball.velocity[0], 0, state.ball.velocity[2]]), 0.6)
      input = {x: dot(push, rightFromYaw(state.camera.yaw)), y: dot(push, forwardFromYaw(state.camera.yaw))}
    }

    const before = state
    state = step(state, input, DT)
    events.push(...state.events.map(e => e.type))

    const lost = state.events.find(e => e.type === "fallout" || e.type === "timeup")
    if (lost) {
      const where = before.ball.position.map(n => n.toFixed(1))
      assert.fail(`${lost.type} at ${where}, heading for waypoint ${target}, clock ${state.clock.toFixed(1)}`)
    }
  }

  return {state, events}
}

const platformTop = (level, index) => state => {
  const p = level.platforms[index]
  return add(colliderAt(p, state.clock).center, [0, p.half[1], 0])
}

test("stage 1 can be finished, picking up gems on the way", () => {
  const {state, events} = autopilot(0, [[0, 0, -9], [0, 0, -23], [9, 0, -24], goalCenter(LEVELS[0])])
  assert.equal(state.phase, "cleared")
  assert.ok(events.includes("goal"))
  assert.ok(state.gems >= 5, `${state.gems} gems`)
})

test("stage 2 can be finished", () => {
  const {state} = autopilot(1, [
    [0, -2, -14],
    [16, -2, -14],
    [16, -2, -30],
    [12, -2, -30],
    goalCenter(LEVELS[1]),
  ].map(at => () => ({at, speed: 4.5, within: 0.8})))
  assert.equal(state.phase, "cleared")
  assert.ok(state.timeLeft > 0)
})

test("stage 3 can be finished by riding both moving platforms", () => {
  const level = LEVELS[2]
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
})

test("clearing a stage banks its gems and moves on; clearing the last starts over", () => {
  const cleared = {...startLevel(0), phase: "cleared", gems: 3}
  const next = advance(cleared)
  assert.equal(next.levelIndex, 1)
  assert.equal(next.banked, 3)

  const last = {...startLevel(LEVELS.length - 1, 9), phase: "cleared"}
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
  const level = LEVELS[0]
  let state = run(newGame(), {x: 0, y: 1}, 3.5)
  assert.ok(state.gems >= 1)

  const scene = buildScene(state, 9 / 16)
  const count = mesh => scene.items.filter(i => i.mesh === mesh).length

  assert.equal(count("sphere"), 1)
  assert.equal(count("torus"), 1)
  assert.equal(count("gem"), level.gems.length - state.gems)
  assert.equal(count("box"), level.platforms.length + 1)

  const [x, y] = mat4TransformPoint(scene.viewProjection, state.ball.position)
  assert.ok(Math.abs(x) < 0.5 && Math.abs(y) < 0.7, `ball at ${x}, ${y}`)
})

test("the camera stays above the leaned stage, even looking back up a ramp at full tilt", () => {
  // stage 2, on the landing at the foot of the downhill ramp, stick hard forward
  const base = startLevel(1)
  const position = [0, -2 + BALL_RADIUS, -12]
  const state = {...base, phase: "playing", tilt: [0, 0, -1], ball: {...base.ball, position}, camera: {yaw: 0, focus: position}}

  for (const aspect of [9 / 19.5, 16 / 9]) {
    const scene = buildScene(state, aspect)
    // The ramp's top face, under the camera: it must be in front of the lens
    // and below the middle of the picture, i.e. seen from above.
    const ramp = LEVELS[1].platforms[1]
    const under = add(ramp.center, scale(ramp.axes[1], ramp.half[1]))
    const [, y, z] = mat4TransformPoint(scene.viewProjection, under)
    assert.ok(z < 1 && y < -0.2, `aspect ${aspect.toFixed(2)}: ramp at y ${y.toFixed(2)}`)
  }
})
