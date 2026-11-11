// Touch first. Put a thumb down anywhere and that spot becomes the centre of
// a stick; drag away from it to lean the page. Lifting the thumb levels it.
// Pointer events cover touch, pen and mouse alike; arrow keys and WASD are
// there for a keyboard.
//
// The rest of the game only ever sees `read()`: an {x, y} pair, each -1..1,
// x to the right and y away from the player.

const REACH = 64

export const createInput = (surface, stick) => {
  const knob = stick.firstElementChild
  const keys = new Set()
  let pointer = null
  let value = {x: 0, y: 0}

  const show = () => {
    stick.style.transform = `translate(${pointer.originX}px, ${pointer.originY}px)`
    knob.style.transform = `translate(${value.x * REACH}px, ${-value.y * REACH}px)`
    stick.dataset.active = "true"
  }

  const down = e => {
    if (pointer || e.target.closest("button, a")) return
    pointer = {id: e.pointerId, originX: e.clientX, originY: e.clientY}
    value = {x: 0, y: 0}
    surface.setPointerCapture?.(e.pointerId)
    show()
    e.preventDefault()
  }

  const move = e => {
    if (!pointer || e.pointerId !== pointer.id) return
    let dx = e.clientX - pointer.originX
    let dy = e.clientY - pointer.originY
    const size = Math.hypot(dx, dy)

    // Past full reach the stick's centre is dragged along behind the thumb,
    // so reversing direction never means travelling back across dead space.
    if (size > REACH) {
      pointer.originX += (dx / size) * (size - REACH)
      pointer.originY += (dy / size) * (size - REACH)
      dx = (dx / size) * REACH
      dy = (dy / size) * REACH
    }

    value = {x: dx / REACH, y: -dy / REACH}
    show()
    e.preventDefault()
  }

  const up = e => {
    if (!pointer || e.pointerId !== pointer.id) return
    pointer = null
    value = {x: 0, y: 0}
    delete stick.dataset.active
  }

  const KEYS = {
    ArrowLeft: [-1, 0], a: [-1, 0],
    ArrowRight: [1, 0], d: [1, 0],
    ArrowUp: [0, 1], w: [0, 1],
    ArrowDown: [0, -1], s: [0, -1],
  }

  const keydown = e => {
    if (KEYS[e.key]) {
      keys.add(e.key)
      e.preventDefault()
    }
  }
  const keyup = e => keys.delete(e.key)
  const blur = () => keys.clear()

  surface.addEventListener("pointerdown", down)
  surface.addEventListener("pointermove", move)
  surface.addEventListener("pointerup", up)
  surface.addEventListener("pointercancel", up)
  window.addEventListener("keydown", keydown)
  window.addEventListener("keyup", keyup)
  window.addEventListener("blur", blur)

  return {
    read() {
      if (pointer) return value
      let x = 0
      let y = 0
      keys.forEach(key => {
        x += KEYS[key][0]
        y += KEYS[key][1]
      })
      return {x: Math.sign(x), y: Math.sign(y)}
    },

    destroy() {
      surface.removeEventListener("pointerdown", down)
      surface.removeEventListener("pointermove", move)
      surface.removeEventListener("pointerup", up)
      surface.removeEventListener("pointercancel", up)
      window.removeEventListener("keydown", keydown)
      window.removeEventListener("keyup", keyup)
      window.removeEventListener("blur", blur)
    },
  }
}
