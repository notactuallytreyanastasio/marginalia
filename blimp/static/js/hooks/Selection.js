(() => {
// Select a passage and both things you can do with it appear at the
// end of it: talk about that spot in its own thread, or carry it into
// the question you are already writing. Two different intentions, and
// guessing which one someone meant gets it wrong half the time.
//
// The text is verified against the manuscript server-side before
// either path keeps it: a browser selection picks up whatever the
// markup puts in its way.
Blimp.hook("Selection", {
  mounted() {
    this.bar = this.el.querySelector("#sel-actions");
    if (!this.bar) return;

    const act = (fn) => (e) => {
      // mousedown, not click: clicking clears the selection first
      e.preventDefault();
      const text = String(window.getSelection() || "").trim();
      const block = this.blockOf(window.getSelection());
      const endBlock = this.endBlockOf(window.getSelection());
      if (text.length >= 12) fn(text, block, endBlock);
      window.getSelection()?.removeAllRanges();
      this.hide();
    };

    this.bar.querySelector("#sel-add").addEventListener("mousedown", act((text) => {
      this.pushEvent("add_context", {text});
    }));

    this.bar.querySelector("#sel-rewrite").addEventListener("mousedown", act((text, block, endBlock) => {
      // The END of the selection, not the start. The panel renders
      // inside the block it names, so anchoring it to the first
      // paragraph of a four-paragraph drag put it above three
      // paragraphs of the thing it was rewriting and nowhere near
      // the cursor. The bar sits at the bottom of the range, so the
      // last block is where the mouse actually is.
      const at = endBlock || block;
      this.pushEvent("suggest_rewrite", {text, ref: at && at.ref});
    }));

    this.bar.querySelector("#sel-discuss").addEventListener("mousedown", act((text, block) => {
      if (!block) return;
      this.pushEvent("open_thread", {
        ref: block.ref,
        section: block.section,
        quote: text,
      });
    }));

    // Where the press landed, so a release can tell a click from a
    // drag. This is the whole reason the paragraph has no invisible
    // hit target over it any more: a <button> covering the prose
    // swallows the drag, and the owner — the only person who saw
    // that overlay — could not select a word of their own draft.
    this.onDown = (e) => { this.down = {x: e.clientX, y: e.clientY}; };
    this.onUp = (e) => {
      requestAnimationFrame(() => this.place());
      this.maybeEdit(e);
    };
    document.addEventListener("mousedown", this.onDown);
    document.addEventListener("mouseup", this.onUp);
    document.addEventListener("keyup", this.onUp);
    this.onScroll = () => this.hide();
    window.addEventListener("scroll", this.onScroll, {passive: true});
  },

  destroyed() {
    document.removeEventListener("mousedown", this.onDown);
    document.removeEventListener("mouseup", this.onUp);
    document.removeEventListener("keyup", this.onUp);
    window.removeEventListener("scroll", this.onScroll);
  },

  // A click inside your own prose opens the paragraph for editing; a
  // drag selects it. The two are told apart by whether anything got
  // selected and whether the pointer travelled, which is how every
  // text surface has always decided this.
  maybeEdit(e) {
    const body = this.el.querySelector(".mg-read-body");
    if (!body || body.dataset.editable !== "true") return;
    if (!e || typeof e.clientX !== "number" || !this.down) return;

    const sel = window.getSelection();
    if (sel && !sel.isCollapsed && String(sel).trim().length) return;
    if (Math.hypot(e.clientX - this.down.x, e.clientY - this.down.y) > 4) return;

    const block = e.target?.closest?.(".mg-block");
    if (!block || !body.contains(block)) return;

    // anything with its own job keeps it: the thread tick, a link in
    // the prose, an open thread or rewrite panel nested in the block
    if (e.target.closest("a, button, input, textarea, form, .mg-thread-panel, .mg-rewrite")) return;

    // A highlight is the note's own affordance — hover peeks,
    // click pins — so a click on one belongs to the margin, not
    // to the editor. With the drawer open that is the whole way
    // a passage gets fed to the conversation, and opening an
    // editor on top of it made adding a second one impossible.
    if (e.target.closest("mark[id]")) return;

    // and with the drawer open the draft is the reference, not
    // the thing being edited
    if (body.closest(".mg-read")?.classList.contains("collapsed")) return;

    this.pushEvent("edit_block", {ref: block.id.replace(/^block-/, "")});
  },

  // which paragraph the selection started in, so a thread can pin to it
  blockOf(sel) {
    if (!sel || !sel.rangeCount) return null;
    let node = sel.getRangeAt(0).startContainer;
    if (node.nodeType === Node.TEXT_NODE) node = node.parentElement;
    const el = node?.closest?.(".mg-block");
    if (!el) return null;
    const tick = el.querySelector(".mg-tick");
    return {ref: el.id.replace(/^block-/, ""), section: tick?.getAttribute("phx-value-section")};
  },

  // The last paragraph the selection actually covers, so the panel
  // opens where the drag finished rather than where it began.
  //
  // NOT endContainer. A drag that stops at the end of a paragraph
  // reports the NEXT node at offset 0 — the range ends *before* it,
  // covering none of it — so three highlighted paragraphs anchored
  // the panel under a fourth that was not selected at all. The
  // boundary comparisons below exclude a block the range merely
  // touches.
  endBlockOf(sel) {
    if (!sel || !sel.rangeCount) return null;
    const range = sel.getRangeAt(0);

    const covered = [...this.el.querySelectorAll(".mg-block")].filter((b) => {
      const br = document.createRange();
      br.selectNodeContents(b);
      // range ends at or before the block starts, or starts at or
      // after it ends: no text of this block is in the selection
      if (range.compareBoundaryPoints(Range.END_TO_START, br) >= 0) return false;
      if (range.compareBoundaryPoints(Range.START_TO_END, br) <= 0) return false;
      return true;
    });

    const el = covered[covered.length - 1];
    if (!el) return null;
    const tick = el.querySelector(".mg-tick");
    return {ref: el.id.replace(/^block-/, ""), section: tick?.getAttribute("phx-value-section")};
  },

  hide() { if (this.bar) this.bar.hidden = true; },

  place() {
    const sel = window.getSelection();
    const text = String(sel || "").trim();
    if (!sel || sel.isCollapsed || text.length < 12) return this.hide();

    const range = sel.getRangeAt(0);
    // only for the draft itself, not for the chat transcript
    if (!this.el.contains(range.commonAncestorContainer)) return this.hide();

    // The WHOLE range has to be in the prose, not just where it
    // started: dragging out of a paragraph and into a margin note
    // used to pass this check and then fail server-side, because the
    // note's words are not in the draft.
    //
    // Both ends, not the common ancestor. A selection inside one
    // paragraph has a text node for an ancestor and passed; a
    // selection across several has the container above them, which
    // is .mg-read-body itself or higher, and `contains` went false —
    // so the rewrite button vanished exactly when the span got
    // interesting. Testing the endpoints says what was meant.
    const body = this.el.querySelector(".mg-read-body");
    const inBody =
      body &&
      body.contains(range.startContainer) &&
      body.contains(range.endContainer);
    this.bar.querySelector("#sel-discuss").hidden = !inBody;
    this.bar.querySelector("#sel-rewrite").hidden = !inBody;

    const r = range.getBoundingClientRect();
    const host = this.el.getBoundingClientRect();
    this.bar.hidden = false;
    this.bar.style.top = `${r.bottom - host.top + 8}px`;
    this.bar.style.left = `${Math.max(0, r.left - host.left)}px`;
  },
});
})();
