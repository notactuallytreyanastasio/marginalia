// Touch first. Put a thumb down anywhere and that spot becomes the centre of
// a stick; drag away from it to lean the page. Lifting the thumb levels it.
// Pointer events cover touch, pen and mouse alike; arrow keys and WASD are
// there for a keyboard, and the left stick of a gamepad where the browser
// lets the page see one.
//
// The rest of the game only ever sees `read()`: an {x, y} pair, each -1..1,
// x to the right and y away from the player, plus a few commands (pause,
// restart, confirm) handed to the `command` callback as they happen. A
// gamepad cannot tell us when its buttons change, so `poll()` has to be
// called once a frame on every screen for them to work.

import type {Input} from "../core/types.ts"

// CSS pixels from the stick's centre to full lean.
const REACH = 64
// Below this fraction of full lean the stick reads as level, so a resting
// thumb (or a worn gamepad) does not creep the ball along.
const DEAD_ZONE = 0.08
// Past the dead zone, lean grows as this power of the distance: a little
// softer than linear near the centre for fine steering, still full at the rim.
const CURVE = 1.4

const STILL: Input = {x: 0, y: 0}

// Keyed by KeyboardEvent.code, so WASD sits in the same place on any layout.
const MOVES: Readonly<Partial<Record<string, readonly [number, number]>>> = {
  ArrowLeft: [-1, 0], KeyA: [-1, 0],
  ArrowRight: [1, 0], KeyD: [1, 0],
  ArrowUp: [0, 1], KeyW: [0, 1],
  ArrowDown: [0, -1], KeyS: [0, -1],
}

export type Command = "pause" | "restart" | "confirm"

const COMMANDS: Readonly<Partial<Record<string, Command>>> = {
  KeyP: "pause",
  Escape: "pause",
  KeyR: "restart",
  Enter: "confirm",
  NumpadEnter: "confirm",
  Space: "confirm",
}

// Standard gamepad mapping: A (or cross) confirms, Start pauses.
const PAD_COMMANDS: readonly (readonly [number, Command])[] = [
  [0, "confirm"],
  [9, "pause"],
]

// Anything a tap is meant for. A thumb landing on one of these never starts
// a drag.
const INTERACTIVE = "button, a, input, select, textarea, [role='button'], .ll-card, [data-ll-nodrag]"

interface Pointer {
  readonly id: number
  // where the stick is centred; dragged along behind a thumb that overreaches
  readonly originX: number
  readonly originY: number
}

export interface InputOptions {
  readonly surface: HTMLElement
  readonly stick: HTMLElement
  readonly command: (command: Command) => void
}

export interface InputReader {
  // asks the gamepad, if any, for its buttons and stick
  poll(): void
  read(): Input
  // While false, no stick is shown and nothing leans; a stick in use is let go.
  setActive(active: boolean): void
  destroy(): void
}

// Dead zone and curve, applied to the length of the vector so diagonals
// behave like any other direction.
export const shape = (x: number, y: number): Input => {
  const size = Math.hypot(x, y)
  if (size <= DEAD_ZONE) return STILL
  const reach = Math.min(1, size)
  const eased = Math.pow((reach - DEAD_ZONE) / (1 - DEAD_ZONE), CURVE)
  return {x: (x / size) * eased, y: (y / size) * eased}
}

// navigator.getGamepads is missing in some browsers and throws where a
// permissions policy forbids it, which a sandboxed frame may well do.
const firstPad = (): Gamepad | null => {
  if (typeof navigator.getGamepads !== "function") return null
  try {
    for (const pad of navigator.getGamepads()) {
      if (pad && pad.connected) return pad
    }
  } catch {
    return null
  }
  return null
}

const typingInto = (target: EventTarget | null): boolean =>
  target instanceof HTMLElement && (target.isContentEditable || target.closest("input, select, textarea") !== null)

export const createInput = ({surface, stick, command}: InputOptions): InputReader => {
  const knob = stick.firstElementChild
  if (!(knob instanceof HTMLElement)) throw new Error("the stick needs a knob element inside it")

  const keys = new Set<string>()
  const padHeld = new Set<number>()
  let pointer: Pointer | null = null
  let value: Input = STILL
  let padStick: Input = STILL
  let active = false

  const show = (at: Pointer): void => {
    stick.style.transform = `translate(${at.originX}px, ${at.originY}px)`
    knob.style.transform = `translate(${value.x * REACH}px, ${-value.y * REACH}px)`
    stick.dataset["active"] = "true"
  }

  const release = (): void => {
    if (pointer) {
      try {
        if (surface.hasPointerCapture(pointer.id)) surface.releasePointerCapture(pointer.id)
      } catch {
        // the pointer is already gone; nothing to release
      }
    }
    pointer = null
    value = STILL
    delete stick.dataset["active"]
  }

  const down = (e: PointerEvent): void => {
    // Only the first finger steers. A second one landing (or a mouse button
    // pressed mid-drag) is ignored rather than allowed to re-centre the stick.
    if (!active || pointer) return
    if (e.pointerType === "mouse" && e.button !== 0) return
    if (e.target instanceof Element && e.target.closest(INTERACTIVE)) return
    pointer = {id: e.pointerId, originX: e.clientX, originY: e.clientY}
    value = STILL
    try {
      surface.setPointerCapture(e.pointerId)
    } catch {
      // without capture the drag still works while the thumb stays on the stage
    }
    show(pointer)
    e.preventDefault()
  }

  const move = (e: PointerEvent): void => {
    if (!pointer || e.pointerId !== pointer.id) return
    let dx = e.clientX - pointer.originX
    let dy = e.clientY - pointer.originY
    const size = Math.hypot(dx, dy)

    // Past full reach the stick's centre is dragged along behind the thumb,
    // so reversing direction never means travelling back across dead space.
    if (size > REACH) {
      pointer = {
        id: pointer.id,
        originX: pointer.originX + (dx / size) * (size - REACH),
        originY: pointer.originY + (dy / size) * (size - REACH),
      }
      dx = (dx / size) * REACH
      dy = (dy / size) * REACH
    }

    // The knob follows the thumb exactly; only the lean is shaped.
    value = {x: dx / REACH, y: -dy / REACH}
    show(pointer)
    e.preventDefault()
  }

  const up = (e: PointerEvent): void => {
    if (pointer && e.pointerId === pointer.id) release()
  }

  const keydown = (e: KeyboardEvent): void => {
    if (e.ctrlKey || e.metaKey || e.altKey || typingInto(e.target)) return
    if (MOVES[e.code]) {
      keys.add(e.code)
      e.preventDefault()
      return
    }
    const which = COMMANDS[e.code]
    if (which === undefined || e.repeat) return
    // A focused button already turns Enter and Space into its own click;
    // confirming as well would press two buttons with one key.
    if (which === "confirm" && e.target instanceof Element && e.target.closest("button")) return
    e.preventDefault()
    command(which)
  }
  const keyup = (e: KeyboardEvent): void => {
    keys.delete(e.code)
  }
  const blur = (): void => {
    keys.clear()
    release()
  }

  const fromKeys = (): Input => {
    let x = 0
    let y = 0
    keys.forEach(code => {
      const [kx, ky] = MOVES[code] ?? [0, 0]
      x += kx
      y += ky
    })
    // A diagonal is full lean, not 1.4 times it.
    const size = Math.hypot(x, y)
    return size === 0 ? STILL : {x: x / size, y: y / size}
  }

  // Buttons are edge-triggered: a held button fires once.
  const fromPad = (): Input => {
    const pad = firstPad()
    if (!pad) {
      padHeld.clear()
      return STILL
    }
    for (const [index, which] of PAD_COMMANDS) {
      const pressed = pad.buttons[index]?.pressed === true
      if (pressed && !padHeld.has(index)) command(which)
      if (pressed) padHeld.add(index)
      else padHeld.delete(index)
    }
    // gamepad y is positive downward, ours away from the player
    return shape(pad.axes[0] ?? 0, -(pad.axes[1] ?? 0))
  }

  surface.addEventListener("pointerdown", down)
  surface.addEventListener("pointermove", move)
  surface.addEventListener("pointerup", up)
  surface.addEventListener("pointercancel", up)
  surface.addEventListener("lostpointercapture", up)
  window.addEventListener("keydown", keydown)
  window.addEventListener("keyup", keyup)
  window.addEventListener("blur", blur)

  return {
    poll() {
      padStick = fromPad()
    },

    read() {
      if (!active) return STILL
      if (pointer) return shape(value.x, value.y)
      if (padStick.x !== 0 || padStick.y !== 0) return padStick
      return fromKeys()
    },

    setActive(next) {
      active = next
      if (!next) release()
    },

    destroy() {
      release()
      surface.removeEventListener("pointerdown", down)
      surface.removeEventListener("pointermove", move)
      surface.removeEventListener("pointerup", up)
      surface.removeEventListener("pointercancel", up)
      surface.removeEventListener("lostpointercapture", up)
      window.removeEventListener("keydown", keydown)
      window.removeEventListener("keyup", keyup)
      window.removeEventListener("blur", blur)
    },
  }
}
