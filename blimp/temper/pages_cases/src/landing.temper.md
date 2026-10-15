# The landing page: /

`LandingLive`. A single document in the bare layout: no app header, no flash
group, no `<main>`. It is the product's pitch with the product's own notes in
the margin beside it, and one button, `just the notes`, that hides the prose
and keeps the notes.

The markup is `landing_markup.temper.md` and the stylesheet
`landing_css.temper.md`, both generated from the verbatim extracts. What this
file adds is the four places the page depends on who is looking (the class on
`div#landing`, the toggle's `on`, the header link, the second call to action),
and the one event.

The page does not mint a guest. It reads the scope the router mounted: a guest
or a real user is a person who has been here, and sees `Your drafts` instead of
`Log in`. Every `Upload a draft` goes to `/works/new`, which is where the guest
is made.

    let { Ctx, webMeta, uiGet, uiPut, uiDelete } = import("webcore/src");
    let { Response } = import("http/src");
    let { JsonObject } = import("std/json");
    let { h, hraw } = import("html/src");

## The four places

`which` is the placeholder the generator left: `NOTES` (a class on the
document), `ON` (a class on the toggle), `HEADLINK` (the third link of the
header) and `LOGINCTA` (the second button of the first section, for a visitor
with no scope only).

    export let pagesCasesLandingDyn(which: String, notesOnly: Boolean, signedIn: Boolean): AnyValue {
      if (which == "NOTES") {
        if (notesOnly) { " notes-only" } else { "" }
      } else if (which == "ON") {
        if (notesOnly) { " on" } else { "" }
      } else if (which == "HEADLINK") {
        if (signedIn) {
          "<a href=\"/works\">Your drafts</a>"
        } else {
          "<a href=\"/users/log-in\">Log in</a>"
        }
      } else if (which == "LOGINCTA") {
        if (signedIn) { "" } else { "<a href=\"/users/log-in\" class=\"cta ghost\">Log in</a>" }
      } else {
        console.log("pages_cases: no landing placeholder ${which}");
        panic()
      }
    }

## State

`notes_only` was a socket assign that started false on every mount. It is a
session flag here, and a plain visit starts it false again, as a mount did.

    let pgcLandingKey(): String { "landing:notes_only" }

    export class LandingState(public notesOnly: Boolean, public signedIn: Boolean) {}

    export let loadLanding(ctx: Ctx): LandingState {
      new LandingState(uiGet(ctx, pgcLandingKey()) == "1", ctx.scope.user != null)
    }

## Render

The stylesheet first (it is the first thing the LiveView rendered), then the
document.

    export let renderLanding(state: LandingState): List<AnyValue> {
      [
        h("style", "", ["\n", hraw(pagesCasesLandingCss()), "\n"]),
        "\n",
        pagesCasesLandingMarkup(state.notesOnly, state.signedIn),
      ]
    }

## GET /

    export let pagesCasesLandingPage(ctx: Ctx): Response throws Bubble {
      if (!ctx.isAjax) { pgcLandingReset(ctx); }
      pagesCasesAnswer(ctx, webMeta(null), renderLanding(loadLanding(ctx)), null, "bare")
    }

    let pgcLandingReset(ctx: Ctx): Void {
      if (uiGet(ctx, pgcLandingKey()) != null) { uiDelete(ctx, pgcLandingKey()); }
    }

## Events

`toggle_notes`: no params, `notes_only = !notes_only`.

    export let pagesCasesLandingEvent(ctx: Ctx, event: String, payload: JsonObject): Response throws Bubble {
      if (event == "toggle_notes") {
        let now = uiGet(ctx, pgcLandingKey()) != "1";
        if (now) { uiPut(ctx, pgcLandingKey(), "1"); } else { uiDelete(ctx, pgcLandingKey()); }
        pagesCasesAnswer(ctx, webMeta(null), renderLanding(loadLanding(ctx)), null, "bare")
      } else {
        pagesCasesUnhandled("/", event)
      }
    }
