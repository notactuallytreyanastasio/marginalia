// A few synthesised blips, so there are no sound files to ship. The audio
// context can only be started from inside a tap, which is why nothing exists
// until `unlock()` is called from one.

const tone = (context, {from, to = from, at = 0, length = 0.12, volume = 0.12, shape = "sine"}) => {
  const start = context.currentTime + at
  const oscillator = context.createOscillator()
  const gain = context.createGain()

  oscillator.type = shape
  oscillator.frequency.setValueAtTime(from, start)
  oscillator.frequency.exponentialRampToValueAtTime(to, start + length)
  gain.gain.setValueAtTime(volume, start)
  gain.gain.exponentialRampToValueAtTime(0.0001, start + length)

  oscillator.connect(gain).connect(context.destination)
  oscillator.start(start)
  oscillator.stop(start + length + 0.02)
}

const SOUNDS = {
  go: c => tone(c, {from: 660, to: 990, length: 0.18, shape: "triangle"}),
  gem: c => {
    tone(c, {from: 1175, length: 0.07, shape: "triangle"})
    tone(c, {from: 1568, at: 0.06, length: 0.12, shape: "triangle"})
  },
  goal: c => [523, 659, 784, 1047].forEach((f, i) => tone(c, {from: f, at: i * 0.09, length: 0.22, shape: "triangle"})),
  fallout: c => tone(c, {from: 520, to: 70, length: 0.7, shape: "sawtooth", volume: 0.07}),
  timeup: c => [330, 262].forEach((f, i) => tone(c, {from: f, at: i * 0.22, length: 0.3, shape: "square", volume: 0.06})),
  bounce: (c, e) => tone(c, {from: 150, to: 55, length: 0.09, volume: 0.05 + 0.15 * e.strength}),
}

export const createAudio = () => {
  let context = null
  let muted = false

  return {
    unlock() {
      const Context = window.AudioContext || window.webkitAudioContext
      if (!context && Context) context = new Context()
      if (context?.state === "suspended") context.resume()
    },

    play(event) {
      if (!muted && context && SOUNDS[event.type]) SOUNDS[event.type](context, event)
    },

    toggle() {
      muted = !muted
      return muted
    },

    destroy() {
      context?.close()
      context = null
    },
  }
}
