// Writes to the DOM only when a value actually changes. The HUD is redrawn
// every frame from the game state, and a steady frame should touch nothing:
// rewriting the same text still costs a style and layout pass on a phone.

export interface Writer {
  text(element: HTMLElement, value: string): void
  // set, or with null remove, a data attribute
  data(element: HTMLElement, name: string, value: string | null): void
  hidden(element: HTMLElement, hidden: boolean): void
  // forget what was written, after something else has changed the DOM
  forget(element: HTMLElement): void
}

export const createWriter = (): Writer => {
  const written = new Map<HTMLElement, Map<string, string | null>>()

  const changed = (element: HTMLElement, slot: string, value: string | null): boolean => {
    let slots = written.get(element)
    if (!slots) {
      slots = new Map()
      written.set(element, slots)
    }
    if (slots.has(slot) && slots.get(slot) === value) return false
    slots.set(slot, value)
    return true
  }

  return {
    text(element, value) {
      if (changed(element, "text", value)) element.textContent = value
    },
    data(element, name, value) {
      if (!changed(element, `data-${name}`, value)) return
      if (value === null) delete element.dataset[name]
      else element.dataset[name] = value
    },
    hidden(element, hidden) {
      if (changed(element, "hidden", hidden ? "1" : null)) element.hidden = hidden
    },
    forget(element) {
      written.delete(element)
    },
  }
}
