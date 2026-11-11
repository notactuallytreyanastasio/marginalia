# Loose Leaf

A marble, a tilting sheet of squared paper, a ring to reach. Served at `/play`.

## Shape

```
core/     pure functions, no DOM, no clock, no WebGL
  math.js      vectors, quaternions, matrices
  physics.js   the physics engine: a rigid sphere against oriented boxes
  levels.js    the stages, as data
  game.js      the rules: step(state, input, dt) -> state
  meshes.js    generated geometry
  scene.js     state -> camera + list of things to draw

shell/    everything with a side effect
  renderer.js  the cel-shading engine (WebGL 1): toon bands + inked outlines
  input.js     touch stick, keyboard
  audio.js     synthesised sound

hook.js   the LiveView hook: owns the loop and the one mutable `state`
```

The shell reads input, hands it to `step`, hands the result to `buildScene`,
and draws what comes back. Nothing in `core/` imports from `shell/`.

## Tests

The core runs under plain Node, no dependencies:

    node --test assets/test/game/*.test.mjs

A scripted player in there finishes every stage, so a level that cannot be
completed fails the suite.

## Adding a stage

Append to `LEVELS` in `core/levels.js`. Platforms are described by their top
surface (`pad`, `slab`, `mover`, `wall`); give the new stage an autopilot route
in the tests.
