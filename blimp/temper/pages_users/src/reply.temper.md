# Answering

What the three pages share: one way to answer with a rendered `<main>` whether
the request was a page or an event, and one way to refuse an event nobody
handles.

    let { Ctx, webMeta, webPage, webEventReply, webPutFlash, webLogIn, webSaveSession } = import("webcore/src");
    let { Response } = import("http/src");
    let { User } = import("accounts/src");

An event answers with the region (and a flash, if given); a plain request, the
POST fallback of a form, answers with the whole page. No page here has a title.

    let puRender(ctx: Ctx, tree: List<AnyValue>, flash: Pair<String, String>?): Response throws Bubble {
      if (ctx.isAjax) {
        webEventReply(ctx, tree, [], flash, null)
      } else {
        let f = flash;
        if (f != null) { webPutFlash(ctx, f.key, f.value); }
        webPage(ctx, webMeta(null), tree, null, "app")
      }
    }

An event the page does not have. A crash with the names in the log is better
than an answer that looks like success.

    let puUnhandledEvent(page: String, event: String): Response throws Bubble {
      console.log("pages_users: ${page} has no event ${event}");
      bubble()
    }

## Logging in with a flash

`webLogIn` clears the old session, flash included, and answers with the
redirect already saved. Phoenix's flash survived `clear_session`, so the flash
is put afterwards and the session saved again; the response is the one
`webLogIn` made.

    let puLogInWithFlash(ctx: Ctx, user: User, remember: Boolean, text: String): Response throws Bubble {
      let r = webLogIn(ctx, user, remember);
      webPutFlash(ctx, "info", text);
      webSaveSession(ctx.db, ctx.session);
      r
    }
