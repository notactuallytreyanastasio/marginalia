# Flash

A flash is one message per kind (`info`, `error`) waiting in the session. It is
put by a handler, survives a redirect, and is taken (read and cleared) by the
next page or event reply that shows it. The Phoenix flash worked the same way
through `phoenix_flash` in the cookie.

    let { attr, h, htext } = import("html/src");
    let { JsonTextProducer, NullInterchangeContext } = import("std/json");

    export let webPutFlash(ctx: Ctx, kind: String, text: String): Void {
      ctx.session.flash = wcMapPut(ctx.session.flash, kind, text);
      ctx.session.dirty = true;
    }

Read and clear.

    export let webTakeFlash(ctx: Ctx): Map<String, String> {
      let got = ctx.session.flash;
      if (got.keys().length > 0) {
        ctx.session.flash = wcEmptyMap();
        ctx.session.dirty = true;
      }
      got
    }

## flash/1

`CoreComponents.flash`. Nothing is rendered unless there is a message: `inner`
(the slot) or `flash[kind]`. `id` defaults to `flash-<kind>`; `hidden` renders
the boolean attribute (the two connection toasts start hidden and `blimp.js`
unhides them).

The `phx-click` that pushed `lv:clear-flash` and hid the toast is not emitted:
the flash is already cleared server-side when it is rendered, and `blimp.js`
hides a toast in `#flash-group` that has no `phx-click` by itself.

    export let cFlash(
      id: String?,
      flash: Map<String, String>,
      title: String?,
      kind: String,
      hidden: Boolean,
      inner: List<AnyValue>?,
    ): List<AnyValue> {
      let fromFlash = flash.getOr(kind, "");
      let slot = inner;
      if (slot == null && fromFlash == "") { return []; }
      let elementId = if (id != null) { id } else { "flash-${kind}" };
      let alertClass = "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap ${if (kind == "info") { "alert-info" } else { "alert-error" }}";
      let message: List<AnyValue> = if (slot != null) { slot } else { htext(fromFlash) };
      let iconName = if (kind == "info") { "hero-information-circle" } else { "hero-exclamation-circle" };
      let titleP: List<AnyValue> = if (title != null) { h("p", attr("class", "font-semibold"), htext(title)) } else { [] };
      h("div", "${attr("id", elementId)}${attr("role", "alert")}${attr("class", "toast toast-top toast-end z-50")}${if (hidden) { " hidden" } else { "" }}", [
        h("div", attr("class", alertClass), [
          cIconClass(iconName, "size-5 shrink-0"),
          h("div", "", [
            titleP,
            h("p", "", [message]),
          ]),
          h("div", attr("class", "flex-1"), []),
          h("button", "${attr("type", "button")}${attr("class", "group self-start cursor-pointer")}${attr("aria-label", "close")}", [
            cIconClass("hero-x-mark", "size-5 opacity-40 group-hover:opacity-70"),
          ]),
        ]),
      ])
    }

## flash_group/1

The two flashes plus the two connection toasts. `blimp.js` finds
`#client-error` (the fetch failed) and `#server-error` (the server answered an
error) by id and toggles `hidden`; it creates `#flash-info` / `#flash-error`
inside `#flash-group` when an event reply carries a flash and none is there.

    export let cFlashGroup(flash: Map<String, String>, id: String?): List<AnyValue> {
      let groupId = if (id != null) { id } else { "flash-group" };
      let reconnect: List<AnyValue> = [
        htext("Attempting to reconnect"),
        cIconClass("hero-arrow-path", "ml-1 size-3 motion-safe:animate-spin"),
      ];
      h("div", "${attr("id", groupId)}${attr("aria-live", "polite")}", [
        cFlash(null, flash, null, "info", false, null),
        cFlash(null, flash, null, "error", false, null),
        cFlash("client-error", flash, "We can't find the internet", "error", true, reconnect),
        cFlash("server-error", flash, "Something went wrong!", "error", true, reconnect),
      ])
    }

The JSON object for the `flash` key of a reply: only the kinds present.

    export let webFlashJson(flash: Map<String, String>): String throws Bubble {
      let p = new JsonTextProducer(NullInterchangeContext.instance);
      wcWriteStringMap(p, flash);
      p.toJsonString()
    }
