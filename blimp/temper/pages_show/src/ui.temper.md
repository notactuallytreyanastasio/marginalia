# The part of the state that only the page knows

One JSON object in the session's ui state, under `show:<slug>`: the filter,
the open thread, the rewrite panel and what the writer put in it, the held
passage, the walkthrough. Everything else about the page is read from the
database again on every request (`state.temper.md`).

The state lives in the session, not in the draft: two tabs of one browser
share it, and another reader of the same draft has their own. A page that is
opened afresh finds the panel as it was left; the Elixir started from nothing.
That is the price of a page with no process, and it is the cheaper of the two
ways to be wrong (the other is a rewrite panel that closes itself every time
the drawer is toggled, because toggling is a navigation here).

    let { Ctx, uiGet, uiPut } = import("webcore/src");
    let { Section, worksSectionById } = import("works/src");
    let { Conversation, chatGetConversation } = import("chat/src");
    let { ReadingFocus, ReadingCite, ReadingPreview, RewriteCandidate } = import("reading/src");
    let { TourCard, tourFor } = import("cases/src");
    let { JsonSyntaxTree, JsonTextProducer } = import("std/json");

    export let showUiKey(slug: String): String { "show:${slug}" }

## Writing

    let psWriteRewrite(p: JsonTextProducer, r: ShowRewrite): Void throws Bubble {
      p.startObject();
      showKeyStr(p, "reading", r.reading);
      showKeyStr(p, "original", r.original);
      showKeyInt(p, "section", r.sectionOrdinal);
      p.objectKey("candidates");
      p.startArray();
      for (let c of r.candidates) {
        p.startObject();
        showKeyStr(p, "text", c.text);
        showKeyStr(p, "move", c.move);
        showKeyStr(p, "cost", c.cost);
        p.endObject();
      }
      p.endArray();
      showKeyBool(p, "spans_blocks", r.spansBlocks);
      showKeyStrings(p, "covers", r.covers);
      p.endObject();
    }

A rewrite as JSON text: what is stored in the ui state, and what a rewrite
job leaves in its run's `detail`.

    export let showRewriteJson(r: ShowRewrite): String throws Bubble {
      let p = showProducer();
      psWriteRewrite(p, r);
      p.toJsonString()
    }

    let psWriteFocus(p: JsonTextProducer, f: ReadingFocus): Void throws Bubble {
      p.startObject();
      showKeyStr(p, "kind", f.kind);
      showKeyStr(p, "title", f.title);
      showKeyStr(p, "body", f.body);
      showKeyStr(p, "quote", f.quote);
      showKeyInts(p, "sections", f.sections.map { (s: Section): Int => s.id });
      p.endObject();
    }

    let psWriteThread(p: JsonTextProducer, c: Conversation): Void throws Bubble {
      p.startObject();
      showKeyInt(p, "id", c.id);
      showKeyStr(p, "block_ref", c.blockRef);
      showKeyInt(p, "section_id", c.sectionId);
      showKeyStr(p, "anchor_kind", c.anchorKind);
      showKeyStr(p, "quote", c.quote);
      showKeyStr(p, "mode", c.mode);
      p.endObject();
    }

The whole object, as text.

    export let showUiJson(state: ShowState): String throws Bubble {
      let p = showProducer();
      p.startObject();
      showKeyStr(p, "only", state.only);
      p.objectKey("focus");
      let focus = state.focus;
      if (focus != null) { psWriteFocus(p, focus); } else { p.nullValue(); }
      p.objectKey("cited");
      p.startArray();
      for (let c of state.cited) {
        p.startObject();
        showKeyStr(p, "text", c.text);
        showKeyStr(p, "section", c.section);
        showKeyInt(p, "ordinal", c.ordinal);
        p.endObject();
      }
      p.endArray();
      let convo = state.conversation;
      showKeyInt(p, "conversation", if (convo != null) { convo.id } else { null });
      p.objectKey("open_thread");
      let thread = state.openThread;
      if (thread != null) { psWriteThread(p, thread); } else { p.nullValue(); }
      showKeyBool(p, "loading", state.loading);
      showKeyBool(p, "thread_loading", state.threadLoading);
      showKeyStrings(p, "mutter", state.mutter);
      showKeyInts(p, "mutter_seen", state.mutterSeen);
      p.objectKey("rewrite");
      let rewrite = state.rewrite;
      if (rewrite != null) { psWriteRewrite(p, rewrite); } else { p.nullValue(); }
      showKeyBool(p, "rewrite_pending", state.rewritePending);
      showKeyStr(p, "rewrite_span", state.rewriteSpan);
      showKeyStr(p, "rewrite_ref", state.rewriteRef);
      showKeyStr(p, "steer", state.steer);
      p.objectKey("preview");
      let preview = state.preview;
      if (preview != null) {
        p.startObject();
        showKeyStr(p, "original", preview.original);
        showKeyStr(p, "text", preview.text);
        p.endObject();
      } else { p.nullValue(); }
      showKeyStr(p, "editing", state.editing);
      showKeyStr(p, "edit_text", state.editText);
      p.objectKey("applied");
      let applied = state.applied;
      if (applied != null) {
        p.startObject();
        showKeyStr(p, "before", applied.before);
        showKeyStr(p, "after", applied.after);
        p.endObject();
      } else { p.nullValue(); }
      showKeyBool(p, "changes_on", state.changesOn);
      showKeyBool(p, "linking", state.linking);
      let tour = state.tour;
      showKeyStr(p, "tour", if (tour != null) { tour.view } else { null });
      showKeyBool(p, "demo", state.demo);
      p.endObject();
      p.toJsonString()
    }

Saved when it differs from what is stored, so a poll writes nothing.

    export let showSaveUi(ctx: Ctx, state: ShowState): Void throws Bubble {
      let key = showUiKey(state.work.slug);
      let text = showUiJson(state);
      let was = uiGet(ctx, key);
      if (was == null || was != text) { uiPut(ctx, key, text); }
    }

## Reading

A field that is not there reads as the empty string (or -1), and the empty
string is "not there" for the fields where it could not be a value.

    let psReadRewrite(t: JsonSyntaxTree?): ShowRewrite? {
      let original = showOr(showJStr(t, "original"), "");
      if (original == "") { return null; }
      let cands = new ListBuilder<RewriteCandidate>();
      for (let c of showJList(t, "candidates")) {
        let text = showOr(showJStr(c, "text"), "");
        if (text != "") {
          cands.add(new RewriteCandidate(text, showJStr(c, "move"), showJStr(c, "cost")));
        }
      }
      new ShowRewrite(
        showJStr(t, "reading"), original, showJInt(t, "section"), cands.toList(),
        showJBool(t, "spans_blocks"), showJStrings(t, "covers"),
      )
    }

A rewrite out of JSON text (the ui state's, or a job's answer), or null when
it is not one.

    export let showRewriteFrom(text: String?): ShowRewrite? {
      psReadRewrite(showParse(text))
    }

    let psFocusOf(ctx: Ctx, state: ShowState, t: JsonSyntaxTree?): ReadingFocus? throws Bubble {
      let kind = showOr(showJStr(t, "kind"), "");
      let title = showOr(showJStr(t, "title"), "");
      if (kind == "" || title == "") { return null; }
      let sections = new ListBuilder<Section>();
      for (let id of showJInts(t, "sections")) {
        let s = worksSectionById(ctx.db, id);
        if (s != null) {
          if (s.workId == state.work.id) { sections.add(s); }
        }
      }
      new ReadingFocus(kind, title, showJStr(t, "body"), showJStr(t, "quote"), sections.toList())
    }

    let psThreadOf(ctx: Ctx, state: ShowState, t: JsonSyntaxTree?): Conversation? throws Bubble {
      let id = showIntOr(showJInt(t, "id"), -1);
      if (id < 0) { return null; }
      if (id == 0) {
        let ref = showOr(showJStr(t, "block_ref"), "");
        if (ref == "") { return null; }
        new Conversation(
          0, state.work.id, null, showOr(showJStr(t, "mode"), "read"),
          showOr(showJStr(t, "anchor_kind"), "block"), showJInt(t, "section_id"),
          ref, showJStr(t, "quote"), null, ctx.now, ctx.now,
        )
      } else {
        chatGetConversation(ctx.db, state.work.id, id)
      }
    }

Fills the **ui** fields of `state` from the session. The ones that name a row
(the conversation, the open thread, the held sections) are looked up again,
and are dropped if the row has gone.

    export let showApplyUi(ctx: Ctx, state: ShowState): Void throws Bubble {
      let t = showParse(uiGet(ctx, showUiKey(state.work.slug)));
      state.only = showJStr(t, "only");
      state.focus = psFocusOf(ctx, state, showField(t, "focus"));
      let cited = new ListBuilder<ReadingCite>();
      for (let c of showJList(t, "cited")) {
        let body = showOr(showJStr(c, "text"), "");
        let ordinal = showIntOr(showJInt(c, "ordinal"), -1);
        if (body != "" && ordinal >= 0) {
          cited.add(new ReadingCite(body, showOr(showJStr(c, "section"), ""), ordinal));
        }
      }
      state.cited = cited.toList();
      state.savedConversation = showJInt(t, "conversation");
      state.openThread = psThreadOf(ctx, state, showField(t, "open_thread"));
      state.loading = showJBool(t, "loading");
      state.threadLoading = showJBool(t, "thread_loading");
      state.mutter = showJStrings(t, "mutter");
      state.mutterSeen = showJInts(t, "mutter_seen");
      state.rewrite = psReadRewrite(showField(t, "rewrite"));
      state.rewritePending = showJBool(t, "rewrite_pending");
      state.rewriteSpan = showJStr(t, "rewrite_span");
      state.rewriteRef = showJStr(t, "rewrite_ref");
      state.steer = showJStr(t, "steer");
      let pv = showField(t, "preview");
      let original = showOr(showJStr(pv, "original"), "");
      if (original != "") {
        state.preview = new ReadingPreview(original, showOr(showJStr(pv, "text"), ""));
      }
      state.editing = showJStr(t, "editing");
      state.editText = showJStr(t, "edit_text");
      let ap = showField(t, "applied");
      let before = showOr(showJStr(ap, "before"), "");
      let after = showOr(showJStr(ap, "after"), "");
      if (before != "" || after != "") { state.applied = new ShowApplied(before, after); }
      state.changesOn = showJBool(t, "changes_on");
      state.linking = showJBool(t, "linking");
      let tourView = showJStr(t, "tour");
      if (tourView != null) { state.tour = tourFor(tourView); }
      state.demo = showJBool(t, "demo");
    }
