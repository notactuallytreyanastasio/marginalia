// The imperative shell, as a LiveView hook. Everything with a side effect
// lives here or under ./shell: the canvas, the clock, the listeners, the
// sound, the DOM. It holds exactly one piece of game data — the current
// state — and replaces it wholesale with whatever the core returns.
//
//   input.read() ──▶ step(state, input, dt) ──▶ buildScene(state) ──▶ renderer.draw
//                          │
//                          └─ state.events ──▶ sound, haptics, HUD

import {advance, elapsed, isLastLevel, newGame, step} from "./core/game.js"
import {LEVELS} from "./core/levels.js"
import {buildMeshes} from "./core/meshes.js"
import {buildScene} from "./core/scene.js"
import {createAudio} from "./shell/audio.js"
import {createInput} from "./shell/input.js"
import {createRenderer} from "./shell/renderer.js"

const STEP = 1 / 60
// Phones with very dense screens gain little past this and pay for it in heat.
const MAX_PIXEL_RATIO = 2

const BANNERS = {
  ready: "Ready",
  fallout: "Off the page",
  timeup: "Out of time",
  goal: "Cleared!",
}

const BUZZ = {gem: 8, goal: [20, 40, 60], fallout: 80, timeup: 80}

export const LooseLeafGame = {
  mounted() {
    const part = name => this.el.querySelector(`[data-ll="${name}"]`)
    this.parts = {
      canvas: part("canvas"),
      level: part("level"),
      time: part("time"),
      gems: part("gems"),
      banner: part("banner"),
      cardTitle: part("card-title"),
      cardBody: part("card-body"),
      action: part("action"),
      mute: part("mute"),
    }

    this.renderer = createRenderer(this.parts.canvas, buildMeshes())
    if (!this.renderer) {
      this.el.dataset.phase = "unsupported"
      return
    }

    this.state = newGame()
    this.started = false
    this.shown = {}
    this.audio = createAudio()
    this.input = createInput(this.el, part("stick"))

    this.onAction = () => {
      this.audio.unlock()
      if (!this.started) this.started = true
      else this.state = advance(this.state)
      this.last = null
    }
    this.onMute = () => {
      const muted = this.audio.toggle()
      this.parts.mute.setAttribute("aria-pressed", String(muted))
    }
    this.onResize = () => this.fit()
    this.onVisibility = () => (this.last = null)

    this.parts.action.addEventListener("click", this.onAction)
    this.parts.mute.addEventListener("click", this.onMute)
    window.addEventListener("resize", this.onResize)
    document.addEventListener("visibilitychange", this.onVisibility)

    this.fit()
    this.frame = requestAnimationFrame(now => this.tick(now))
  },

  fit() {
    const ratio = Math.min(window.devicePixelRatio || 1, MAX_PIXEL_RATIO)
    const {clientWidth, clientHeight} = this.parts.canvas
    this.renderer.resize(Math.round(clientWidth * ratio), Math.round(clientHeight * ratio))
    this.aspect = clientWidth / Math.max(1, clientHeight)
  },

  tick(now) {
    this.frame = requestAnimationFrame(next => this.tick(next))

    // A fixed step keeps the physics identical at 60, 90 and 120 Hz. After a
    // stall (tab hidden, phone locked) the backlog is dropped, not replayed.
    const since = this.last == null ? 0 : Math.min(0.1, (now - this.last) / 1000)
    this.last = now

    if (this.started) {
      this.owed = (this.owed || 0) + since
      const input = this.input.read()
      while (this.owed >= STEP) {
        this.state = step(this.state, input, STEP)
        this.state.events.forEach(event => this.react(event))
        this.owed -= STEP
      }
    }

    this.renderer.draw(buildScene(this.state, this.aspect))
    this.updateHud()
  },

  react(event) {
    this.audio.play(event)
    if (BUZZ[event.type] && navigator.vibrate) navigator.vibrate(BUZZ[event.type])
  },

  // The HUD is ordinary DOM over the canvas. Each value is written only when
  // its text changes, so a steady frame touches nothing.
  updateHud() {
    const state = this.state
    const level = LEVELS[state.levelIndex]
    const phase = this.started ? state.phase : "title"

    const show = (key, text) => {
      if (this.shown[key] === text) return
      this.shown[key] = text
      this.parts[key].textContent = text
    }

    if (this.shown.phase !== phase) {
      this.shown.phase = phase
      this.el.dataset.phase = phase
    }

    show("level", `${state.levelIndex + 1} · ${level.name}`)
    show("time", state.timeLeft.toFixed(1))
    show("gems", `${state.gems}/${level.gems.length}`)
    show("banner", phase === "ready" && state.attempts === 1 ? level.hint : BANNERS[phase] || "")

    if (phase === "title") {
      show("cardTitle", "Loose Leaf")
      show("cardBody", "Roll the marble to the ring before the clock runs out. Drag anywhere to tilt the page.")
      show("action", "Play")
    } else if (phase === "cleared") {
      const last = isLastLevel(state)
      const total = state.banked + state.gems
      show("cardTitle", last ? "All pages cleared" : `${level.name} cleared`)
      show(
        "cardBody",
        `${elapsed(state).toFixed(1)}s · ${state.gems} of ${level.gems.length} gems` +
          (last ? ` · ${total} in all` : ""),
      )
      show("action", last ? "Play again" : "Next page")
    }
  },

  destroyed() {
    cancelAnimationFrame(this.frame)
    if (!this.renderer) return
    this.input.destroy()
    this.audio.destroy()
    this.parts.action.removeEventListener("click", this.onAction)
    this.parts.mute.removeEventListener("click", this.onMute)
    window.removeEventListener("resize", this.onResize)
    document.removeEventListener("visibilitychange", this.onVisibility)
  },
}
