// The imperative shell. Everything with a side effect lives here or under
// ./shell: the canvas, the clock, the listeners, the sound, the DOM, the
// stored records. It holds exactly one piece of game data — the current
// state — and replaces it wholesale with whatever the core returns.
//
//   input.read() ──▶ step(state, input, dt) ──▶ buildScene(state) ──▶ renderer.draw
//                          │
//                          └─ state.events ──▶ sound, haptics, HUD
//
// Around the game sit the screens (title, stage select, playing, paused,
// results); ./shell/screens.ts decides which leads to which, and this file
// carries out each move.

import {advance, elapsed, isLastLevel, levelCount, medalFor, restart, startLevel, step} from "./core/game.ts"
import type {Medal} from "./core/game.ts"
import {levelAt} from "./core/levels.ts"
import {buildMeshes} from "./core/meshes.ts"
import {buildScene} from "./core/scene.ts"
import type {GameEvent, GameState, Phase} from "./core/types.ts"
import {createAudio} from "./shell/audio.ts"
import {bootWithHot} from "./shell/hot.ts"
import type {HotSnapshot} from "./shell/hot.ts"
import {createWriter} from "./shell/hud.ts"
import {createInput} from "./shell/input.ts"
import type {Command} from "./shell/input.ts"
import {startLoop} from "./shell/loop.ts"
import {createRenderer} from "./shell/renderer.ts"
import {hasCard, nextScreen} from "./shell/screens.ts"
import type {Screen, UiAction} from "./shell/screens.ts"
import {loadProgress, recordFinish, saveProgress} from "./shell/storage.ts"
import type {Progress} from "./shell/storage.ts"

// Phones with very dense screens gain little past this and pay for it in heat.
const MAX_PIXEL_RATIO = 2
// A ceiling on the drawing buffer as a whole, for big screens: every pass
// is paid per pixel, and past about a phone's worth the picture gains little.
const MAX_PIXELS = 1_600_000
// Under this many seconds the clock chip turns urgent.
const URGENT = 10

const BANNERS: Readonly<Record<Phase, string>> = {
  ready: "Ready",
  playing: "",
  cleared: "",
  fallout: "Off the page",
  timeup: "Out of time",
  goal: "Cleared!",
}

const MEDAL_NAMES: Readonly<Record<Medal, string>> = {gold: "Gold", silver: "Silver", bronze: "Bronze"}
const MEDALS: readonly Medal[] = ["gold", "silver", "bronze"]

const buzz = (event: GameEvent): VibratePattern | null => {
  switch (event.type) {
    case "gem":
      return 8
    case "goal":
      return [20, 40, 60]
    case "fallout":
    case "timeup":
      return 80
    case "bumper":
      return 14
    case "go":
    case "bounce":
      // the start has its own sound, and bounces are too frequent to buzz for
      return null
    default: {
      const unreachable: never = event
      return unreachable
    }
  }
}

// Vibration is a courtesy; a sandboxed frame may refuse it outright.
const vibrate = (pattern: VibratePattern): void => {
  try {
    if (typeof navigator.vibrate === "function") navigator.vibrate(pattern)
  } catch {
    // no buzz, then
  }
}

const seconds = (value: number): string => `${value.toFixed(1)}s`

// --- the page ------------------------------------------------------------------

interface Parts {
  readonly canvas: HTMLCanvasElement
  readonly stick: HTMLElement
  readonly pause: HTMLButtonElement
  readonly mute: HTMLButtonElement
  readonly level: HTMLElement
  readonly levelNumber: HTMLElement
  readonly time: HTMLElement
  readonly timeChip: HTMLElement
  readonly gems: HTMLElement
  readonly speed: HTMLElement
  readonly banner: HTMLElement
  readonly card: HTMLElement
  readonly cardKicker: HTMLElement
  readonly cardTitle: HTMLElement
  readonly cardBody: HTMLElement
  readonly grid: HTMLElement
  readonly results: HTMLElement
  readonly medal: HTMLElement
  readonly medalName: HTMLElement
  readonly resultTime: HTMLElement
  readonly resultGems: HTMLElement
  readonly resultBest: HTMLElement
  readonly callout: HTMLElement
  readonly par: Readonly<Record<Medal, HTMLElement>>
  readonly action: HTMLButtonElement
  readonly secondary: HTMLButtonElement
  readonly tertiary: HTMLButtonElement
}

const findParts = (root: HTMLElement): Parts => {
  const part = <T extends Element>(name: string, type: {new (): T; prototype: T}): T => {
    const element = root.querySelector(`[data-ll="${name}"]`)
    if (!(element instanceof type)) {
      throw new Error(`Loose Leaf: no ${type.name} with data-ll="${name}" in the page`)
    }
    return element
  }

  return {
    canvas: part("canvas", HTMLCanvasElement),
    stick: part("stick", HTMLElement),
    pause: part("pause", HTMLButtonElement),
    mute: part("mute", HTMLButtonElement),
    level: part("level", HTMLElement),
    levelNumber: part("level-number", HTMLElement),
    time: part("time", HTMLElement),
    timeChip: part("time-chip", HTMLElement),
    gems: part("gems", HTMLElement),
    speed: part("speed", HTMLElement),
    banner: part("banner", HTMLElement),
    card: part("card", HTMLElement),
    cardKicker: part("card-kicker", HTMLElement),
    cardTitle: part("card-title", HTMLElement),
    cardBody: part("card-body", HTMLElement),
    grid: part("grid", HTMLElement),
    results: part("results", HTMLElement),
    medal: part("medal", HTMLElement),
    medalName: part("medal-name", HTMLElement),
    resultTime: part("result-time", HTMLElement),
    resultGems: part("result-gems", HTMLElement),
    resultBest: part("result-best", HTMLElement),
    callout: part("callout", HTMLElement),
    par: {gold: part("par-gold", HTMLElement), silver: part("par-silver", HTMLElement), bronze: part("par-bronze", HTMLElement)},
    action: part("action", HTMLButtonElement),
    secondary: part("secondary", HTMLButtonElement),
    tertiary: part("tertiary", HTMLButtonElement),
  }
}

// What the results card shows, worked out once when the stage is cleared.
interface Finish {
  readonly stage: number
  readonly seconds: number
  readonly gems: number
  readonly total: number
  readonly medal: Medal | null
  readonly bestTime: number
  readonly newBestTime: boolean
  readonly newBestGems: boolean
  readonly firstClear: boolean
  readonly perfect: boolean
}

// A card button: its label and what it does, or null to hide it.
interface Choice {
  readonly label: string
  readonly action: () => void
}

export const start = (root: HTMLElement): void => {
  const parts = findParts(root)

  const renderer = createRenderer(parts.canvas, buildMeshes())
  if (!renderer) {
    root.dataset["phase"] = "unsupported"
    root.dataset["screen"] = "unsupported"
    delete root.dataset["booting"]
    return
  }

  const stages = levelCount()
  let progress: Progress = loadProgress()
  const audio = createAudio(progress.muted)
  const write = createWriter()

  // The one piece of mutable game data, and the screen around it.
  let state: GameState = startLevel(0)
  let screen: Screen = "title"
  let finish: Finish | null = null
  let aspect = 1
  // what each card button does on the current screen
  // whether the last thing the player touched was the keyboard
  let keyboardLast = false
  let choices: readonly [Choice | null, Choice | null, Choice | null] = [null, null, null]

  // --- progress ----------------------------------------------------------------

  const recordOf = (index: number) => progress.stages[levelAt(index).name]
  const unlocked = (index: number): boolean => index === 0 || recordOf(index - 1) !== undefined
  // The stage a plain "Play" means: the first not yet cleared, else the
  // stage last played.
  const suggested = (): number => {
    for (let i = 0; i < stages; i++) if (recordOf(i) === undefined) return i
    return Math.min(state.levelIndex, stages - 1)
  }

  // --- moves between screens ------------------------------------------------------

  const go = (action: UiAction, effect: () => void): void => {
    const next = nextScreen(screen, action)
    if (next === null) return
    effect()
    screen = next
    showScreen()
  }

  const play = (index: number): void =>
    go("play", () => {
      state = startLevel(index)
      finish = null
    })
  const pause = (): void => go("pause", () => audio.cue("pause"))
  const resume = (): void => go("resume", () => audio.cue("resume"))
  const again = (): void =>
    go("restart", () => {
      state = restart(state)
      finish = null
    })
  const toStages = (): void => go("stages", () => undefined)
  const back = (): void => go("back", () => undefined)
  const next = (): void =>
    go("play", () => {
      state = advance(state)
      finish = null
    })

  const cleared = (): void =>
    go("finish", () => {
      const level = levelAt(state.levelIndex)
      const time = elapsed(state)
      const medal = medalFor(level, time)
      const before = progress.stages[level.name]
      const recorded = recordFinish(progress, level.name, {seconds: time, gems: state.gems, medal})
      progress = recorded.progress
      saveProgress(progress)
      finish = {
        stage: state.levelIndex,
        seconds: time,
        gems: state.gems,
        total: level.gems.length,
        medal,
        bestTime: progress.stages[level.name]?.bestTime ?? time,
        newBestTime: recorded.newBestTime,
        newBestGems: recorded.newBestGems,
        firstClear: before === undefined,
        perfect: state.perfect,
      }
      if (recorded.newBestTime) audio.cue("best")
    })

  // --- the card -----------------------------------------------------------------------

  const tile = (index: number): HTMLElement => {
    const level = levelAt(index)
    const record = recordOf(index)
    const open = unlocked(index)

    const item = document.createElement("div")
    item.setAttribute("role", "listitem")
    const button = document.createElement("button")
    button.type = "button"
    button.className = "ll-tile"
    button.id = `loose-leaf-stage-${index + 1}`
    button.disabled = !open
    button.dataset["medal"] = record?.medal ?? "none"
    if (!open) button.dataset["locked"] = "true"

    const number = document.createElement("span")
    number.className = "ll-tile-number"
    number.textContent = String(index + 1)
    const name = document.createElement("span")
    name.className = "ll-tile-name"
    name.textContent = level.name
    const detail = document.createElement("span")
    detail.className = "ll-tile-detail"
    detail.textContent = !open ? "Locked" : record ? `Best ${seconds(record.bestTime)}` : "Not cleared"
    const badge = document.createElement("span")
    badge.className = "ll-tile-medal"
    badge.setAttribute("aria-hidden", "true")

    button.append(number, name, detail, badge)
    const medal = record?.medal
    button.setAttribute(
      "aria-label",
      `Stage ${index + 1}, ${level.name}: ` +
        (!open ? "locked" : record ? `best ${seconds(record.bestTime)}${medal ? `, ${MEDAL_NAMES[medal]} medal` : ""}` : "not cleared"),
    )
    button.addEventListener("click", () => {
      tapped()
      play(index)
    })
    item.append(button)
    return item
  }

  const fillResults = (done: Finish): void => {
    const level = levelAt(done.stage)
    parts.medal.dataset["medal"] = done.medal ?? "none"
    parts.medalName.textContent = done.medal ? `${MEDAL_NAMES[done.medal]} medal` : "No medal"
    parts.resultTime.textContent = seconds(done.seconds)
    parts.resultGems.textContent = `${done.gems}/${done.total}`
    parts.resultBest.textContent = seconds(done.bestTime)
    for (const medal of MEDALS) {
      const cell = parts.par[medal]
      cell.textContent = seconds(level.par[medal])
      const row = cell.parentElement
      if (row) row.toggleAttribute("data-earned", done.medal === medal)
    }

    const notes: string[] = []
    if (done.newBestTime) notes.push("New best time!")
    if (done.newBestGems) notes.push("Most gems yet!")
    if (done.firstClear && done.perfect) notes.push("Every gem, first go!")
    else if (done.perfect && notes.length === 0) notes.push("Every gem!")
    if (done.firstClear && notes.length === 0) notes.push("First clear!")
    if (done.medal !== "gold") {
      const target = done.medal === "silver" ? level.par.gold : done.medal === "bronze" ? level.par.silver : level.par.bronze
      const goal = done.medal === "silver" ? "gold" : done.medal === "bronze" ? "silver" : "bronze"
      notes.push(`${seconds(target)} for ${goal}`)
    }
    parts.callout.textContent = notes.join(" · ")
    parts.callout.dataset["best"] = done.newBestTime || done.newBestGems ? "true" : "false"
  }

  const setChoice = (button: HTMLButtonElement, choice: Choice | null): void => {
    button.hidden = choice === null
    button.textContent = choice?.label ?? ""
  }

  const fillCard = (): void => {
    const level = levelAt(state.levelIndex)
    let kicker = ""
    let title = ""
    let body = ""

    switch (screen) {
      case "title": {
        const first = suggested()
        title = "Loose Leaf"
        body = "Roll the marble to the ring before the clock runs out. Drag anywhere to tilt the page."
        choices = [
          {label: first === 0 && recordOf(0) === undefined ? "Play" : `Play ${levelAt(first).name}`, action: () => play(first)},
          {label: "Stages", action: toStages},
          null,
        ]
        break
      }
      case "select": {
        const first = suggested()
        kicker = `${Object.keys(progress.stages).length} of ${stages} cleared`
        title = "Pick a page"
        parts.grid.replaceChildren(...Array.from({length: stages}, (_, i) => tile(i)))
        choices = [{label: `Play ${levelAt(first).name}`, action: () => play(first)}, {label: "Back", action: back}, null]
        break
      }
      case "paused":
        kicker = `Stage ${state.levelIndex + 1}`
        title = "Paused"
        body = level.name
        choices = [
          {label: "Resume", action: resume},
          {label: "Restart", action: again},
          {label: "Stages", action: toStages},
        ]
        break
      case "results": {
        const last = isLastLevel(state)
        kicker = `Stage ${state.levelIndex + 1} cleared`
        title = last ? "All pages cleared" : level.name
        if (finish) fillResults(finish)
        choices = last
          ? [{label: "Stages", action: toStages}, {label: "Retry", action: again}, null]
          : [
              {label: `Next: ${levelAt(state.levelIndex + 1).name}`, action: next},
              {label: "Retry", action: again},
              {label: "Stages", action: toStages},
            ]
        break
      }
      case "playing":
        choices = [null, null, null]
        return
      default: {
        const unreachable: never = screen
        return unreachable
      }
    }

    parts.cardKicker.textContent = kicker
    parts.cardTitle.textContent = title
    parts.cardBody.textContent = body
    setChoice(parts.action, choices[0])
    setChoice(parts.secondary, choices[1])
    setChoice(parts.tertiary, choices[2])
  }

  // Everything that changes only when the screen does.
  const showScreen = (): void => {
    root.dataset["screen"] = screen
    input.setActive(screen === "playing")
    if (screen !== "playing") audio.hush()
    loop.reset()
    fillCard()
    if (hasCard(screen) && keyboardLast) {
      // Keyboard players land on the primary button. Touch and mouse players
      // are left alone, or a ring would sit on a button nobody aimed at.
      const primary = screen === "select" ? parts.grid.querySelector<HTMLButtonElement>(".ll-tile:not(:disabled)") : parts.action
      ;(primary ?? parts.action).focus({preventScroll: true})
    } else if (document.activeElement instanceof HTMLElement && parts.card.contains(document.activeElement)) {
      document.activeElement.blur()
    }
  }

  // --- the HUD, written every frame but only where something changed -----------------

  const updateHud = (): void => {
    const level = levelAt(state.levelIndex)
    write.data(root, "phase", screen === "title" ? "title" : state.phase)

    write.text(parts.levelNumber, `${state.levelIndex + 1}`)
    write.text(parts.level, level.name)
    write.text(parts.time, state.timeLeft.toFixed(1))
    write.data(parts.timeChip, "urgent", state.phase === "playing" && state.timeLeft < URGENT ? "true" : null)
    write.text(parts.gems, `${state.gems}/${level.gems.length}`)

    write.text(parts.speed, state.speed.toFixed(1))

    const banner =
      screen !== "playing"
        ? ""
        : state.phase === "ready" && state.attempts === 1
          ? level.hint
          : state.phase === "goal" && state.perfect
            ? "Clean sweep!"
            : BANNERS[state.phase]
    write.text(parts.banner, banner)
  }

  // --- the loop --------------------------------------------------------------------------

  const react = (event: GameEvent): void => {
    audio.play(event)
    const pattern = buzz(event)
    if (pattern !== null) vibrate(pattern)
  }

  const loop = startLoop({
    running: () => screen === "playing",
    step: dt => {
      if (screen !== "playing") return
      state = step(state, input.read(), dt)
      state.events.forEach(react)
      if (state.phase === "cleared") cleared()
    },
    draw: () => {
      if (screen === "playing") audio.roll(state.speed, state.grounded)
      renderer.draw(buildScene(state, aspect))
      updateHud()
    },
  })

  // --- input ---------------------------------------------------------------------------

  // Every tap on a button is also the user gesture the audio context waits for.
  const tapped = (): void => {
    audio.unlock()
    audio.cue("tap")
  }

  const command = (which: Command): void => {
    audio.unlock()
    switch (which) {
      case "pause":
        if (screen === "playing") pause()
        else if (screen === "paused") resume()
        else if (screen === "select") back()
        return
      case "restart":
        again()
        return
      case "confirm":
        if (hasCard(screen)) choices[0]?.action()
        return
      default: {
        const unreachable: never = which
        return unreachable
      }
    }
  }

  const input = createInput({surface: root, stick: parts.stick, command})
  window.addEventListener("keydown", () => (keyboardLast = true), {capture: true})
  window.addEventListener("pointerdown", () => (keyboardLast = false), {capture: true})

  const bindChoice = (button: HTMLButtonElement, slot: 0 | 1 | 2): void => {
    button.addEventListener("click", () => {
      tapped()
      choices[slot]?.action()
    })
  }
  bindChoice(parts.action, 0)
  bindChoice(parts.secondary, 1)
  bindChoice(parts.tertiary, 2)

  parts.pause.addEventListener("click", () => {
    audio.unlock()
    pause()
  })

  const showMute = (): void => {
    const muted = audio.muted()
    parts.mute.setAttribute("aria-pressed", String(muted))
    parts.mute.setAttribute("aria-label", muted ? "Unmute sound" : "Mute sound")
  }
  parts.mute.addEventListener("click", () => {
    audio.unlock()
    audio.setMuted(!audio.muted())
    progress = {...progress, muted: audio.muted()}
    saveProgress(progress)
    showMute()
    audio.cue("tap")
  })
  showMute()

  // A hidden tab is a paused game: the clock must not run while nobody looks.
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) {
      pause()
      audio.hush()
    }
    loop.reset()
  })

  // --- size ------------------------------------------------------------------------------

  const fit = (): void => {
    // A page shown without a viewport tag is laid out wide and shrunk to fit
    // the phone; the visual viewport's scale says by how much, so the canvas
    // is sized to the screen's real pixels and not to 980 CSS px of them.
    const shown = window.visualViewport?.scale ?? 1
    const density = (window.devicePixelRatio || 1) * (Number.isFinite(shown) && shown > 0 ? shown : 1)
    const {clientWidth, clientHeight} = parts.canvas
    const area = Math.max(1, clientWidth * clientHeight)
    const ratio = Math.max(0.5, Math.min(density, MAX_PIXEL_RATIO, Math.sqrt(MAX_PIXELS / area)))
    renderer.resize(Math.max(1, Math.round(clientWidth * ratio)), Math.max(1, Math.round(clientHeight * ratio)))
    aspect = clientWidth / Math.max(1, clientHeight)
  }
  if (typeof ResizeObserver === "function") new ResizeObserver(fit).observe(parts.canvas)
  // a zoom changes devicePixelRatio without changing the canvas's CSS size
  window.addEventListener("resize", fit)
  window.visualViewport?.addEventListener("resize", fit)
  fit()

  // --- boot -------------------------------------------------------------------------------

  const snapshot = (): HotSnapshot => ({stage: state.levelIndex, screen})

  // A republish lands back on the same stage. A game in progress comes back
  // paused at the top of its stage, since its exact state did not travel;
  // results come back as the stage grid, since the run they described did not.
  const resumeFrom = (saved: HotSnapshot | null): void => {
    delete root.dataset["booting"]
    if (saved === null || saved.stage >= stages) {
      showScreen()
      return
    }
    state = startLevel(saved.stage)
    switch (saved.screen) {
      case "playing":
      case "paused":
        screen = "paused"
        break
      case "results":
      case "select":
        screen = "select"
        break
      case "title":
        screen = "title"
        break
      default: {
        const unreachable: never = saved.screen
        screen = unreachable
      }
    }
    showScreen()
  }

  bootWithHot(snapshot, resumeFrom)
}

const root = document.getElementById("loose-leaf")
if (!root) throw new Error('Loose Leaf: the page has no element with id "loose-leaf"')
start(root)
