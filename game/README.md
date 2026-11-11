# Loose Leaf

A marble, a tilting sheet of squared paper, a ring to reach. One
self-contained page, `dist/loose-leaf.html`, with nothing fetched at run time.

## Shape

```
src/core/    pure functions, no DOM, no clock, no WebGL, no Math.random
  types.ts     the shared, readonly types everything else is written against
  math.ts      vectors, quaternions, matrices, a seeded PRNG
  physics.ts   the physics engine: a rigid sphere against oriented boxes
  levels.ts    the stages, as data, with their par times
  game.ts      the rules: step(state, input, dt) -> state; medals
  meshes.ts    generated geometry
  scene.ts     state -> camera + list of things to draw

src/shell/   everything with a side effect
  renderer.ts  the cel-shading engine (WebGL 1): toon bands + inked outlines
  input.ts     touch stick, keyboard
  audio.ts     synthesised sound

src/main.ts  start(root): owns the loop and the one mutable `state`
src/page.html, src/style.css   the DOM and styles inlined into the page
```

The shell reads input, hands it to `step`, hands the result to `buildScene`,
and draws what comes back. Nothing in `core/` imports from `shell/`, and any
randomness the core needs comes from `state.seed`, so a run is replayable.

## Commands

    npm run typecheck   tsc, as strict as it goes
    npm test            node --test; Node 22 runs the .ts tests directly
    npm run check:any   fails on `any`, `as unknown as` or a @ts- directive
    npm run build       writes dist/loose-leaf.html

A scripted player in the tests finishes every stage, so a level that cannot
be completed fails the suite, and its times are what the par times are set
from.

## Adding a stage

Append to `LEVELS` in `src/core/levels.ts`. Platforms are described by their
top surface (`pad`, `slab`, `mover`, `wall`); give the new stage par times and
an autopilot route in the tests.
