// Synthesised sound, so there are no sound files to ship. The audio context
// can only be started from inside a tap, which is why nothing exists until
// `unlock()` is called from one.
//
// Everything runs through one master gain, so muting is a fade on a single
// node instead of a check in every voice. Under it sit the one-shot blips for
// game events and one continuous voice: the marble rolling over paper,
// filtered noise whose pitch and loudness follow the ball's speed.

import type {GameEvent} from "../core/types.ts"

// Older Safari only has the prefixed constructor.
declare global {
  interface Window {
    readonly webkitAudioContext?: typeof AudioContext
  }
}

const MASTER = 0.9
// m/s at which the rolling sound is at its loudest and brightest
const ROLL_TOP_SPEED = 9
const ROLL_VOLUME = 0.11

interface Tone {
  readonly from: number
  readonly to?: number
  readonly at?: number
  readonly length?: number
  readonly volume?: number
  readonly shape?: OscillatorType
}

const tone = (
  context: AudioContext,
  out: AudioNode,
  {from, to = from, at = 0, length = 0.12, volume = 0.12, shape = "sine"}: Tone,
): void => {
  const start = context.currentTime + at
  const oscillator = context.createOscillator()
  const gain = context.createGain()

  oscillator.type = shape
  oscillator.frequency.setValueAtTime(from, start)
  oscillator.frequency.exponentialRampToValueAtTime(to, start + length)
  // a few milliseconds of attack, so the start does not click
  gain.gain.setValueAtTime(0.0001, start)
  gain.gain.exponentialRampToValueAtTime(volume, start + 0.006)
  gain.gain.exponentialRampToValueAtTime(0.0001, start + length)

  oscillator.connect(gain).connect(out)
  oscillator.start(start)
  oscillator.stop(start + length + 0.02)
}

// One sound per game event. The switch is exhaustive, so an event type
// added to the core does not compile until it has a sound here.
const sound = (c: AudioContext, out: AudioNode, event: GameEvent): void => {
  switch (event.type) {
    case "go":
      tone(c, out, {from: 660, to: 990, length: 0.18, shape: "triangle"})
      return
    case "gem":
      tone(c, out, {from: 1175, length: 0.07, shape: "triangle"})
      tone(c, out, {from: 1568, at: 0.06, length: 0.12, shape: "triangle"})
      return
    case "goal":
      ;[523, 659, 784, 1047].forEach((f, i) => tone(c, out, {from: f, at: i * 0.09, length: 0.22, shape: "triangle"}))
      return
    case "fallout":
      tone(c, out, {from: 520, to: 70, length: 0.7, shape: "sawtooth", volume: 0.07})
      return
    case "timeup":
      ;[330, 262].forEach((f, i) => tone(c, out, {from: f, at: i * 0.22, length: 0.3, shape: "square", volume: 0.06}))
      return
    case "bounce":
      tone(c, out, {from: 150, to: 55, length: 0.09, volume: 0.05 + 0.15 * event.strength})
      return
    case "bumper":
      // a springy boing: a quick rise and a wobbling fall
      tone(c, out, {from: 220, to: 660, length: 0.06, shape: "square", volume: 0.05})
      tone(c, out, {from: 660, to: 180, at: 0.05, length: 0.22, shape: "triangle", volume: 0.12})
      return
    default: {
      const unreachable: never = event
      return unreachable
    }
  }
}

// Interface noises, kept apart from game events because they are not part
// of the game's state.
export type Cue = "tap" | "pause" | "resume" | "best"

const cue = (c: AudioContext, out: AudioNode, which: Cue): void => {
  switch (which) {
    case "tap":
      tone(c, out, {from: 520, to: 600, length: 0.05, shape: "triangle", volume: 0.06})
      return
    case "pause":
      tone(c, out, {from: 600, to: 400, length: 0.12, shape: "triangle", volume: 0.07})
      return
    case "resume":
      tone(c, out, {from: 400, to: 600, length: 0.12, shape: "triangle", volume: 0.07})
      return
    case "best":
      ;[784, 988, 1319].forEach((f, i) => tone(c, out, {from: f, at: 0.25 + i * 0.08, length: 0.18, shape: "triangle", volume: 0.09}))
      return
    default: {
      const unreachable: never = which
      return unreachable
    }
  }
}

// A second of white noise, looped, as the raw grain of the rolling sound.
const noiseBuffer = (c: AudioContext): AudioBuffer => {
  const buffer = c.createBuffer(1, c.sampleRate, c.sampleRate)
  const data = buffer.getChannelData(0)
  // A tiny LCG rather than Math.random only so the grain is the same every
  // time; nothing depends on it.
  let seed = 0x1234567
  for (let i = 0; i < data.length; i++) {
    seed = (Math.imul(seed, 1103515245) + 12345) | 0
    data[i] = ((seed >>> 16) & 0x7fff) / 0x4000 - 1
  }
  return buffer
}

interface Voices {
  readonly context: AudioContext
  readonly master: GainNode
  readonly rollGain: GainNode
  readonly rollFilter: BiquadFilterNode
}

const build = (context: AudioContext, muted: boolean): Voices => {
  const master = context.createGain()
  master.gain.value = muted ? 0 : MASTER
  master.connect(context.destination)

  const source = context.createBufferSource()
  source.buffer = noiseBuffer(context)
  source.loop = true
  const rollFilter = context.createBiquadFilter()
  rollFilter.type = "bandpass"
  rollFilter.frequency.value = 300
  rollFilter.Q.value = 1.2
  const rollGain = context.createGain()
  rollGain.gain.value = 0
  source.connect(rollFilter).connect(rollGain).connect(master)
  source.start()

  return {context, master, rollGain, rollFilter}
}

export interface Audio {
  unlock(): void
  play(event: GameEvent): void
  cue(which: Cue): void
  // speed in m/s across the page
  roll(speed: number, grounded: boolean): void
  // silence the rolling voice, for pauses and cards
  hush(): void
  setMuted(muted: boolean): void
  muted(): boolean
  destroy(): void
}

// A browser that will not resume or close a context has nothing useful to
// say about it, and the game plays on silently either way.
const ignore = (): void => undefined

export const createAudio = (startMuted: boolean): Audio => {
  let voices: Voices | null = null
  let muted = startMuted

  // How fast the rolling voice follows the ball: quick enough to hear a
  // bump, slow enough not to crackle at frame rate.
  const glide = (param: AudioParam, target: number, context: AudioContext, time = 0.06): void => {
    param.setTargetAtTime(target, context.currentTime, time)
  }

  return {
    unlock() {
      if (!voices) {
        const Context = window.AudioContext ?? window.webkitAudioContext
        if (!Context) return
        try {
          voices = build(new Context(), muted)
        } catch {
          // no audio device, or the browser refused: play on in silence
          return
        }
      }
      if (voices.context.state === "suspended") voices.context.resume().catch(ignore)
    },

    play(event) {
      if (voices && !muted) sound(voices.context, voices.master, event)
    },

    cue(which) {
      if (voices && !muted) cue(voices.context, voices.master, which)
    },

    roll(speed, grounded) {
      if (!voices) return
      const pace = !grounded ? 0 : Math.min(1, speed / ROLL_TOP_SPEED)
      // a square-root rise, so slow rolling is already audible
      glide(voices.rollGain.gain, ROLL_VOLUME * Math.sqrt(pace), voices.context)
      glide(voices.rollFilter.frequency, 180 + 1400 * pace, voices.context)
    },

    hush() {
      if (voices) glide(voices.rollGain.gain, 0, voices.context, 0.03)
    },

    setMuted(next) {
      muted = next
      if (voices) glide(voices.master.gain, muted ? 0 : MASTER, voices.context, 0.04)
    },

    muted() {
      return muted
    },

    destroy() {
      voices?.context.close().catch(ignore)
      voices = null
    },
  }
}
