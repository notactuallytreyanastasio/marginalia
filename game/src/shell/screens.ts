// Which card is up. The game itself has phases (ready, playing, goal...);
// around it the shell has screens, and this is the whole of how one leads to
// another:
//
//   title ──▶ select ──▶ playing ◀──▶ paused
//     │          ▲          │           │
//     └──────────┼──────────┤           │
//                │          ▼           │
//                └────── results ◀──────┘ (stages from either)
//
// `nextScreen` says where an action leads from a screen, or null where the
// action means nothing there (pausing on the title card, say). main.ts does
// the side effects; this only decides.

export type Screen = "title" | "select" | "playing" | "paused" | "results"

export type UiAction =
  // start a stage (from the title, the grid or a results card)
  | "play"
  | "stages"
  | "back"
  | "pause"
  | "resume"
  | "restart"
  // the core reports the stage cleared
  | "finish"

export const nextScreen = (screen: Screen, action: UiAction): Screen | null => {
  switch (action) {
    case "play":
      return screen === "title" || screen === "select" || screen === "results" ? "playing" : null
    case "stages":
      return screen === "title" || screen === "paused" || screen === "results" ? "select" : null
    case "back":
      return screen === "select" ? "title" : null
    case "pause":
      return screen === "playing" ? "paused" : null
    case "resume":
      return screen === "paused" ? "playing" : null
    case "restart":
      return screen === "playing" || screen === "paused" || screen === "results" ? "playing" : null
    case "finish":
      return screen === "playing" ? "results" : null
    default: {
      const unreachable: never = action
      return unreachable
    }
  }
}

// Screens with a card over the picture, as opposed to the game in play.
export const hasCard = (screen: Screen): boolean => screen !== "playing"
