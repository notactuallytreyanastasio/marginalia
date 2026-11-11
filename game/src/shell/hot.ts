// When the page is open in the artifact viewer and gets republished, the
// viewer can hand the new version a snapshot from the old one, so a player
// mid-game lands back where they were instead of on the title card.
//
// The viewer offers this through an optional `window.claude.hot`. Outside the
// viewer (a browser opening the file, a test) it is absent, and so may any of
// its members be, so each is checked before it is called and the game boots
// plainly without it.

import type {Screen} from "./screens.ts"

export interface HotSnapshot {
  readonly stage: number
  readonly screen: Screen
}

interface ClaudeHot {
  // the viewer calls `take` just before the page is replaced
  readonly register?: (take: () => HotSnapshot) => void
  // the viewer calls `boot` once, with the previous page's snapshot if any
  readonly ready?: (boot: (snapshot: unknown) => void) => void
}

declare global {
  interface Window {
    readonly claude?: {readonly hot?: ClaudeHot}
  }
}

const SCREENS: readonly Screen[] = ["title", "select", "playing", "paused", "results"]

const isScreen = (value: unknown): value is Screen => SCREENS.some(screen => screen === value)

export const isHotSnapshot = (value: unknown): value is HotSnapshot =>
  typeof value === "object" &&
  value !== null &&
  "stage" in value &&
  typeof value.stage === "number" &&
  Number.isInteger(value.stage) &&
  value.stage >= 0 &&
  "screen" in value &&
  isScreen(value.screen)

// If the viewer never answers, boot anyway: a missing snapshot must not
// mean a missing game.
const READY_TIMEOUT = 1500

// Calls `boot` exactly once: with the viewer's snapshot when there is a valid
// one, else with null.
export const bootWithHot = (take: () => HotSnapshot, boot: (snapshot: HotSnapshot | null) => void): void => {
  let booted = false
  const once = (snapshot: HotSnapshot | null): void => {
    if (booted) return
    booted = true
    boot(snapshot)
  }

  let hot: ClaudeHot | undefined
  try {
    hot = window.claude?.hot
  } catch {
    hot = undefined
  }
  if (!hot) {
    once(null)
    return
  }

  try {
    if (typeof hot.register === "function") hot.register(take)
  } catch {
    // a viewer that cannot keep a snapshot just means a fresh start next time
  }

  if (typeof hot.ready !== "function") {
    once(null)
    return
  }
  window.setTimeout(() => once(null), READY_TIMEOUT)
  try {
    hot.ready(snapshot => once(isHotSnapshot(snapshot) ? snapshot : null))
  } catch {
    once(null)
  }
}
