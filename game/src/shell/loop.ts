// The frame loop. The simulation moves in fixed 1/60 s steps so the physics
// is the same at 60, 90 and 120 Hz; the picture is drawn once per animation
// frame, whatever the rate.
//
// `paced` is the arithmetic on its own, without the clock, so it can be
// reasoned about (and tested) apart from requestAnimationFrame.

export const STEP = 1 / 60
// A slow phone that falls behind catches up a few steps at a time; past this
// the rest is dropped, or it would spend every frame catching up and never
// draw one.
export const MAX_STEPS = 5
// A gap this long is a stall (tab hidden, phone locked, a debugger), not
// slow frames. It is not replayed: the game carries on from where it was.
export const STALL = 0.25

export interface Paced {
  readonly steps: number
  readonly owed: number
}

// How many steps to run for `since` seconds of wall time on top of `owed`
// left over from before.
export const paced = (owed: number, since: number): Paced => {
  const total = owed + (since > STALL ? STEP : Math.max(0, since))
  const steps = Math.floor(total / STEP + 1e-9)
  if (steps > MAX_STEPS) return {steps: MAX_STEPS, owed: 0}
  return {steps, owed: Math.max(0, total - steps * STEP)}
}

export interface LoopHooks {
  // once per frame, before anything else and on every screen, so devices that
  // have to be asked (a gamepad) are heard even while the game is stopped
  readonly poll: () => void
  // whether the simulation should run this frame
  readonly running: () => boolean
  readonly step: (dt: number) => void
  readonly draw: () => void
}

export interface Loop {
  // forget the time of the last frame, so a pause or a stall is not owed
  readonly reset: () => void
  readonly stop: () => void
}

export const startLoop = (hooks: LoopHooks): Loop => {
  let last: number | null = null
  let owed = 0
  let frame = 0

  const tick = (now: number): void => {
    frame = requestAnimationFrame(tick)
    const since = last === null ? 0 : (now - last) / 1000
    last = now

    hooks.poll()
    if (hooks.running()) {
      const next = paced(owed, since)
      owed = next.owed
      for (let i = 0; i < next.steps; i++) hooks.step(STEP)
    } else {
      owed = 0
    }
    hooks.draw()
  }

  frame = requestAnimationFrame(tick)

  return {
    reset() {
      last = null
      owed = 0
    },
    stop() {
      cancelAnimationFrame(frame)
    },
  }
}
