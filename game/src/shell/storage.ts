// What the game remembers between visits: the best run on each stage and
// whether the sound is off. It all sits under one key, with a version
// number in it, so a later shape can tell old data apart instead of
// misreading it.
//
// Storage is a nice-to-have. In a sandboxed frame or a private window
// localStorage can be missing, empty, full or throw on the mere property
// access, so every touch is wrapped and the game plays on from defaults.
// What comes back out is `unknown` until a hand-written guard has looked at
// every field: a stored value is somebody else's data, not ours.

import type {Medal} from "../core/game.ts"

const KEY = "loose-leaf/v1"
const VERSION = 1

export interface StageRecord {
  // seconds, the fastest finish
  readonly bestTime: number
  // the most gems picked up on any finish
  readonly bestGems: number
  readonly medal: Medal | null
}

export interface Progress {
  // keyed by stage name, so adding or reordering stages keeps old records
  readonly stages: Readonly<Record<string, StageRecord>>
  readonly muted: boolean
}

interface Stored extends Progress {
  readonly version: typeof VERSION
}

export const EMPTY_PROGRESS: Progress = {stages: {}, muted: false}

const isMedal = (value: unknown): value is Medal | null =>
  value === null || value === "gold" || value === "silver" || value === "bronze"

const isCount = (value: unknown): value is number => typeof value === "number" && Number.isFinite(value) && value >= 0

const isStageRecord = (value: unknown): value is StageRecord =>
  typeof value === "object" &&
  value !== null &&
  "bestTime" in value &&
  isCount(value.bestTime) &&
  "bestGems" in value &&
  isCount(value.bestGems) &&
  "medal" in value &&
  isMedal(value.medal)

const isStageTable = (value: unknown): value is Readonly<Record<string, StageRecord>> => {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return false
  const entries: readonly (readonly [string, unknown])[] = Object.entries(value)
  return entries.every(([, record]) => isStageRecord(record))
}

export const isStored = (value: unknown): value is Stored =>
  typeof value === "object" &&
  value !== null &&
  "version" in value &&
  value.version === VERSION &&
  "muted" in value &&
  typeof value.muted === "boolean" &&
  "stages" in value &&
  isStageTable(value.stages)

// Text from storage to progress. Anything unreadable or of another version
// counts as no progress at all, rather than half of something.
export const parseProgress = (text: string | null): Progress => {
  if (text === null) return EMPTY_PROGRESS
  let value: unknown
  try {
    value = JSON.parse(text)
  } catch {
    return EMPTY_PROGRESS
  }
  return isStored(value) ? {stages: value.stages, muted: value.muted} : EMPTY_PROGRESS
}

export const serializeProgress = (progress: Progress): string => {
  const stored: Stored = {version: VERSION, stages: progress.stages, muted: progress.muted}
  return JSON.stringify(stored)
}

export const loadProgress = (): Progress => {
  try {
    return parseProgress(window.localStorage.getItem(KEY))
  } catch {
    return EMPTY_PROGRESS
  }
}

// Returns whether it stuck. Nobody needs to act on a failure; it only means
// the next visit starts fresh.
export const saveProgress = (progress: Progress): boolean => {
  try {
    window.localStorage.setItem(KEY, serializeProgress(progress))
    return true
  } catch {
    return false
  }
}

const MEDAL_RANK: Readonly<Record<Medal, number>> = {bronze: 1, silver: 2, gold: 3}
const rank = (medal: Medal | null): number => (medal === null ? 0 : MEDAL_RANK[medal])

export interface Finish {
  readonly seconds: number
  readonly gems: number
  readonly medal: Medal | null
}

export interface Recorded {
  readonly progress: Progress
  readonly newBestTime: boolean
  readonly newBestGems: boolean
}

// Folds one finished run into the records. Each best is kept on its own, so
// a slow run that found every gem still counts for the gems.
export const recordFinish = (progress: Progress, stage: string, finish: Finish): Recorded => {
  const before = progress.stages[stage]
  const newBestTime = before === undefined || finish.seconds < before.bestTime
  const newBestGems = before === undefined || finish.gems > before.bestGems
  const record: StageRecord = {
    bestTime: newBestTime ? finish.seconds : before.bestTime,
    bestGems: newBestGems ? finish.gems : before.bestGems,
    medal: before === undefined || rank(finish.medal) > rank(before.medal) ? finish.medal : before.medal,
  }
  return {
    progress: {...progress, stages: {...progress.stages, [stage]: record}},
    // a first finish is a best by default, but only worth a callout once
    // there was something to beat
    newBestTime: newBestTime && before !== undefined,
    newBestGems: newBestGems && before !== undefined,
  }
}
