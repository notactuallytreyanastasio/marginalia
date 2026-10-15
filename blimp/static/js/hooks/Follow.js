(() => {
// The left column is read; the right one is driven.
//
// A focus line a third of the way down the left column decides what
// you are "on". Whichever linked paragraph last crossed it is the
// current one, and the right column is scrolled to put its
// counterpart at the same height. Reading is the input; nothing has
// to be clicked.
Blimp.hook("Follow", {
  // Every element this hook touches, looked up in one place.
  //
  // These used to be cached once in mounted() and never again.
  // A server re-render — dismissing the one-time card is enough —
  // can replace those nodes, and the hook then holds detached
  // ones: it adds the open class to a `.fl-mid` that is no longer
  // in the document, so a tap highlights the paragraph and the
  // reference never appears. Nothing throws, nothing logs, and
  // the feature is simply dead until reload.
  cache() {
    this.lead = this.el.querySelector("#fl-lead");
    this.other = this.el.querySelector("#fl-other");
    this.strip = this.el.querySelector(".fl-strip");
    this.sheet = this.el.querySelector(".fl-sheet");
    this.stack = this.el.querySelector(".fl-stack");
    this.svg = this.el.querySelector(".fl-wire");
    this.split = this.el.querySelector(".fl-split");
    this.idle = this.el.querySelector(".fl-idle");
    this.count = this.el.querySelector(".fl-count b");
    this.mid = this.el.querySelector(".fl-mid");
  },

  mounted() {
    this.cache();

    // clicking the line carries both passages into the chat;
    // delegated for the same reason as the sheet's controls
    this.onWireClick = (e) => {
      if (e.target.closest(".fl-wire .hit") && this.edge) {
        this.pushEvent("cite_edge", {edge: this.edge});
      }
    };
    this.el.addEventListener("click", this.onWireClick);

    // The chip's menu, in both columns. Delegated for the reason
    // everything else here is: a server patch replaces these nodes
    // and a listener bound to one of them stops working silently.
    this.onJump = (e) => {
      const item = e.target.closest(".fl-jump");
      if (item && !item.disabled) this.jump(item);
    };
    this.el.addEventListener("click", this.onJump);

    // Hovering an entry lights its far paragraph without committing
    // to it, so the menu answers "which three" before you pick one.
    this.onPeek = (e) => {
      const item = e.target.closest(".fl-jump");
      this.peek(item && !item.disabled ? item : null);
    };
    this.el.addEventListener("mouseover", this.onPeek);
    this.el.addEventListener("mouseout", this.onPeek);

    this.seen = new Set();
    this.current = null;

    this.onScroll = () => {
      if (this.queued) return;
      this.queued = true;
      requestAnimationFrame(() => { this.queued = false; this.follow(); });
    };

    this.lead.addEventListener("scroll", this.onScroll, {passive: true});
    // the right column moves under the wire too, by its own scroll
    // or by being driven, so it has to redraw as well
    this.other.addEventListener("scroll", () => this.wire(), {passive: true});

    // The two columns scroll; nothing else on the page does. That
    // leaves the strip between them — 17rem in the dead centre of
    // the screen, exactly where a cursor rests — and the bar at the
    // top as places where the wheel does nothing at all, which
    // reads as "this page will not scroll". Anywhere that is not a
    // column drives the one being read.
    this.onWheel = (e) => {
      if (e.target.closest(".fl-col")) return;
      this.lead.scrollTop += e.deltaY;
      e.preventDefault();
    };
    this.el.addEventListener("wheel", this.onWheel, {passive: false});
    // reading the right-hand document by hand should not be fought
    this.other.addEventListener("wheel", () => this.release(), {passive: true});
    window.addEventListener("resize", this.onScroll);

    // A tap on a highlighted passage picks it, rather than making
    // someone scroll it past the focus line. On a phone, where
    // the other column is not on screen at all, that is the only
    // way to point at something.
    this.onTap = (e) => {
      // the chip's menu picks one edge out of several; letting the
      // tap handler run too would immediately re-select the first
      if (e.target.closest(".fl-jump")) return;
      const block = e.target.closest(".fl-block.linked");
      if (!block) return;
      if (window.getSelection()?.toString()) return;
      this.current = block;
      this.free = false;
      this.mark(block);

      if (this.phone()) {
        if (this.fillStack(block)) {
          this.sheet.hidden = false;
          this.strip.hidden = true;
          this.stack.scrollTop = 0;
          this.openSheet();
        }
      } else {
        this.align(block);
      }
    };
    this.lead.addEventListener("click", this.onTap);

    this.onSheetKey = (e) => {
      if (e.key === "Escape" && this.mid?.classList.contains("open")) this.closeSheet();
    };
    document.addEventListener("keydown", this.onSheetKey);

    // Delegated, not bound to the nodes themselves: a patch can
    // replace them, and a listener on a node that is no longer in
    // the document is a control that silently stops working.
    this.onSheetClick = (e) => {
      // asking about it takes you into the chat, so the reference
      // gets out of the way rather than sitting on top of it
      // The stack's cards are created here, not rendered by the
      // server, so LiveView never bound their clicks — the hook
      // sends the event itself.
      const ask = e.target.closest(".fl-card .ask");
      if (ask) {
        if (ask.dataset.edge) this.pushEvent("cite_edge", {edge: ask.dataset.edge});
        return this.closeSheet();
      }

      // The strip's ask is the same gesture as clicking the drawn
      // line, so it sends the same event. It used to be a server
      // `phx-click` whose edge id the hook wrote on with
      // setAttribute — a server-owned attribute patched from JS,
      // paired with a handler clause that silently did nothing when
      // the attribute was missing. One path, pushed from here, is
      // both shorter and impossible to half-wire.
      const stripAsk = e.target.closest(".fl-strip .ask");
      if (stripAsk) {
        if (this.edge) this.pushEvent("cite_edge", {edge: this.edge});
        return;
      }

      if (e.target.closest(".shut")) {
        return this.closeSheet();
      }
      // the dimmed part, outside the sheet itself
      if (e.target.classList && e.target.classList.contains("fl-mid")) {
        return this.closeSheet();
      }
    };
    this.el.addEventListener("click", this.onSheetClick);

    this.follow();
  },

  updated() {
    // the patch may have swapped the nodes underneath us
    const wasOpen = this.mid?.classList.contains("open");
    this.cache();
    if (wasOpen) this.mid?.classList.add("open");

    this.seen.clear();
    this.current = null;
    this.follow();
  },

  destroyed() {
    document.documentElement.classList.remove("fl-sheet-open");
    document.removeEventListener("keydown", this.onSheetKey);
    this.lead.removeEventListener("click", this.onTap);
    this.el.removeEventListener("click", this.onSheetClick);
    this.el.removeEventListener("click", this.onWireClick);
    this.el.removeEventListener("click", this.onJump);
    this.el.removeEventListener("mouseover", this.onPeek);
    this.el.removeEventListener("mouseout", this.onPeek);
    this.lead.removeEventListener("scroll", this.onScroll);
    this.el.removeEventListener("wheel", this.onWheel);
    cancelAnimationFrame(this.frame);
    window.removeEventListener("resize", this.onScroll);
  },

  release() { this.free = true; },

  // A phone has no room for a second column and no room for a
  // permanent strip either: the screenshot that killed the last
  // design had six hundred pixels of chrome, a sliver of reading
  // and a sheet competing with it for the rest. So the reference
  // is a place you go and come back from.
  phone() { return window.matchMedia("(max-width: 1100px)").matches; },

  // The sheet scrolls, and it kept its position between passages,
  // so it opened halfway down the previous one. Defined here with
  // the other methods rather than as a closure in mounted(),
  // where deleting the code above it took this with it and left
  // mark() calling a function that no longer existed — which
  // threw after the highlight and before the sheet, so a tap lit
  // the paragraph and did nothing else.
  rewind() { if (this.strip) this.strip.scrollTop = 0; },

  // One card per connection on the tapped paragraph, in the order
  // the page has them. Built here rather than rendered by the
  // server because the server does not know which paragraph a
  // thumb landed on, and shipping every paragraph's stack up
  // front would be the whole document twice.
  fillStack(block) {
    const notes = [...block.querySelectorAll("[data-peer-ref]")];
    if (!notes.length) return false;

    this.sheet.querySelector(".n").textContent =
      notes.length === 1 ? "1 connection" : `${notes.length} connections`;

    this.stack.replaceChildren(
      ...notes.map((note) => {
        const card = document.createElement("article");
        card.className = `fl-card k-${note.dataset.kind}`;

        const peer = this.other.querySelector(
          `#blk-other-${CSS.escape(note.dataset.peerRef || "")}`
        );
        const prose = peer
          ? [...peer.querySelectorAll("p")].map((el) => el.textContent.trim()).join(" ")
          : "";

        const head = document.createElement("header");
        const rel = document.createElement("span");
        rel.className = "rel";
        rel.textContent = (note.dataset.kind || "").replace(/_/g, " ");
        const src = document.createElement("span");
        src.className = "src";
        src.textContent = note.dataset.src || "";
        head.append(rel, src);

        const why = document.createElement("p");
        why.className = "why";
        why.textContent = note.dataset.why || "";

        const ask = document.createElement("button");
        ask.type = "button";
        ask.className = "ask";
        ask.dataset.edge = note.dataset.edge || "";
        ask.textContent = "ask about this";

        card.append(head, why);

        if (prose) {
          const far = document.createElement("blockquote");
          far.className = "far";
          far.textContent = prose;
          card.append(far);
        }

        card.append(ask);
        return card;
      })
    );

    return true;
  },

  openSheet() {
    this.mid.classList.add("open");
    document.documentElement.classList.add("fl-sheet-open");
  },

  closeSheet() {
    this.mid.classList.remove("open");
    document.documentElement.classList.remove("fl-sheet-open");
  },

  // The linked paragraph you are currently on: the last one to have
  // crossed the focus line while still being on screen. The "still
  // on screen" half matters — without it a paragraph scrolled past
  // ten screens ago stays selected through every unlinked stretch,
  // and the right-hand column sits on something you cannot see.
  currentBlock() {
    const box = this.lead.getBoundingClientRect();
    const line = box.top + this.lead.clientHeight * 0.33;
    let passed = null;
    let upcoming = null;

    for (const b of this.lead.querySelectorAll(".fl-block.linked")) {
      const r = b.getBoundingClientRect();
      if (r.bottom < box.top || r.top > box.bottom) continue;
      if (r.top <= line) passed = b;
      else if (!upcoming) upcoming = b;
    }

    // nothing has crossed the line yet but something is coming: show
    // it rather than nothing, so the right column is never blank
    // while a link is plainly visible
    return passed || upcoming;
  },

  follow() {
    // nothing to follow with: the reference is not on screen and
    // the reader opens it deliberately
    if (this.phone()) return;

    // A jump from the right column scrolls the left one, and that
    // scroll fires this. Without the hold, follow() re-picks
    // whatever paragraph the smooth scroll is currently passing
    // and the pair you asked for is gone before it arrives.
    if (performance.now() < (this.hold || 0)) return;

    const block = this.currentBlock();
    if (!block) return this.blank();

    if (block !== this.current) {
      this.current = block;
      this.free = false;
      this.mark(block);
    }

    if (!this.free) this.align(block);
  },

  // One entry of the chip's menu. The button carries only the edge
  // id; the note itself is the hidden span already on the paragraph,
  // which is where every other path here reads a relation from.
  jump(item) {
    const edge = item.dataset.edge;
    const block = item.closest(".fl-block");
    const mine = block.querySelector(`[data-peer-ref][data-edge="${CSS.escape(edge)}"]`);
    if (!mine) return;

    this.peek(null);

    // Clicked in the left column: this paragraph is the near end,
    // and the right column comes to meet it.
    if (this.lead.contains(block)) {
      this.current = block;
      this.free = false;
      this.mark(block, mine);

      if (this.phone()) {
        if (this.fillStack(block)) {
          this.sheet.hidden = false;
          this.strip.hidden = true;
          this.stack.scrollTop = 0;
          this.openSheet();
        }
      } else {
        this.align(block, mine);
      }
      return;
    }

    // Clicked in the right column, where the far end is a paragraph
    // of the document being read. Go there rather than to it: the
    // left column is the one with the reading position in it.
    const ref = mine.dataset.peerRef;
    const target = ref && this.lead.querySelector(`#blk-lead-${CSS.escape(ref)}`);
    if (!target) return;

    const note =
      target.querySelector(`[data-peer-ref][data-edge="${CSS.escape(edge)}"]`) ||
      target.querySelector("[data-peer-ref]");

    const to =
      target.getBoundingClientRect().top -
      this.lead.getBoundingClientRect().top +
      this.lead.scrollTop -
      this.lead.clientHeight * 0.28;

    this.hold = performance.now() + 1200;
    this.lead.scrollTo({top: Math.max(0, to), behavior: "smooth"});

    this.current = target;
    this.free = false;
    this.mark(target, note);
    this.chase();
  },

  // The far paragraph of the entry under the cursor, lit but not
  // chosen. A class of its own: `on` is the committed pair, and
  // borrowing it would leave two pairs highlighted at once.
  peek(item) {
    this.el.querySelectorAll(".fl-block.peek").forEach((b) => b.classList.remove("peek"));
    if (!item) return;

    const here = item.closest(".fl-block");
    const far = this.lead.contains(here) ? this.other : this.lead;
    const side = far === this.other ? "other" : "lead";
    const ref = item.dataset.peerRef;
    if (!ref) return;

    far.querySelector(`#blk-${side}-${CSS.escape(ref)}`)?.classList.add("peek");
  },

  // `pick` is the specific edge to show. It defaults to the first
  // one on the paragraph, which is what scrolling past it means,
  // but a hub paragraph has several and the chip's menu names one.
  mark(block, pick) {
    const note = pick || block.querySelector("[data-peer-ref]");
    if (!note) return;

    this.lead.querySelectorAll(".fl-block.on").forEach((b) => b.classList.remove("on"));
    this.other.querySelectorAll(".fl-block.on").forEach((b) => b.classList.remove("on"));
    block.classList.add("on", "seen");

    const peer = this.other.querySelector(`#blk-other-${note.dataset.peerRef}`);
    peer?.classList.add("on");

    this.strip.hidden = false;
    this.idle.hidden = true;
    this.strip.dataset.kind = note.dataset.kind;
    this.strip.querySelector(".rel").textContent = note.dataset.kind.replace(/_/g, " ");
    this.strip.querySelector(".why").textContent = note.dataset.why;

    this.seen.add(note.dataset.edge);
    this.count.textContent = this.seen.size;
    this.strip.querySelector(".nth").textContent = note.dataset.src;

    // The passage on the other side, for the half of the screen a
    // phone does not have. The paragraphs only: the block also
    // holds the relation tag
    // and the hidden spans carrying this data, and on a phone the
    // column is display:none, where innerText falls back to
    // textContent and would sweep both of them in
    const far = this.strip.querySelector(".far");
    const prose = peer
      ? [...peer.querySelectorAll("p")].map((el) => el.textContent.trim()).join(" ")
      : "";
    far.textContent = prose;
    far.hidden = !prose;
    this.svg.dataset.kind = note.dataset.kind;
    // what the strip's ask button will cite, read at click time
    this.edge = note.dataset.edge;
    this.rewind();
    this.chase();
  },

  // the right column is scrolled smoothly, so the wire has to follow
  // it rather than be drawn once against where it used to be
  chase() {
    cancelAnimationFrame(this.frame);
    const until = performance.now() + 900;
    const step = () => {
      this.wire();
      if (performance.now() < until) this.frame = requestAnimationFrame(step);
    };
    step();
  },

  wire() {
    const l = this.lead.querySelector(".fl-block.on");
    const r = this.other.querySelector(".fl-block.on");
    if (!l || !r || this.strip.hidden) return this.svg.setAttribute("hidden", "");

    const box = this.split.getBoundingClientRect();
    const lb = l.getBoundingClientRect();
    const rb = r.getBoundingClientRect();
    const card = this.strip.getBoundingClientRect();
    const lc = this.lead.getBoundingClientRect();
    const rc = this.other.getBoundingClientRect();

    // a passage scrolled out of its own column is not connected to
    // anything the reader can see
    const on = (b, c) => b.bottom > c.top + 4 && b.top < c.bottom - 4;
    if (!on(lb, lc) || !on(rb, rc)) return this.svg.setAttribute("hidden", "");

    // below the sticky column head, so the line never runs under it
    const clamp = (y, c) => Math.max(c.top + 44, Math.min(y, c.bottom - 8));
    const y1 = clamp(lb.top + lb.height / 2, lc) - box.top;
    const y4 = clamp(rb.top + rb.height / 2, rc) - box.top;
    const ym = card.top + card.height / 2 - box.top;

    const x1 = lb.right - box.left;
    const x2 = card.left - box.left - 6;
    const x3 = card.right - box.left + 6;
    const x4 = rb.left - box.left;

    this.svg.removeAttribute("hidden");
    this.svg.setAttribute("viewBox", `0 0 ${box.width} ${box.height}`);
    const d1 = `M ${x1} ${y1} C ${(x1 + x2) / 2} ${y1}, ${(x1 + x2) / 2} ${ym}, ${x2} ${ym}`;
    const d2 = `M ${x3} ${ym} C ${(x3 + x4) / 2} ${ym}, ${(x3 + x4) / 2} ${y4}, ${x4} ${y4}`;
    this.svg.querySelector(".w1").setAttribute("d", d1);
    this.svg.querySelector(".w2").setAttribute("d", d2);
    this.svg.querySelector(".h1").setAttribute("d", d1);
    this.svg.querySelector(".h2").setAttribute("d", d2);
    this.svg.querySelector(".d1").setAttribute("cx", x1);
    this.svg.querySelector(".d1").setAttribute("cy", y1);
    this.svg.querySelector(".d2").setAttribute("cx", x4);
    this.svg.querySelector(".d2").setAttribute("cy", y4);
  },

  // put the cited passage at the same height as the one being read
  align(block, pick) {
    const note = pick || block.querySelector("[data-peer-ref]");
    const peer = note && this.other.querySelector(`#blk-other-${CSS.escape(note.dataset.peerRef || "")}`);
    if (!peer) return;

    // offsetTop is measured from the offsetParent, which is not the
    // scroll container — the two only agree by accident. Work in
    // viewport coordinates and add the scroll back on.
    const want = block.getBoundingClientRect().top - this.lead.getBoundingClientRect().top;
    const peerTop =
      peer.getBoundingClientRect().top -
      this.other.getBoundingClientRect().top +
      this.other.scrollTop;

    const to = Math.max(0, Math.min(peerTop - want, this.other.scrollHeight - this.other.clientHeight));

    if (Math.abs(this.other.scrollTop - to) > 2) {
      this.other.scrollTo({top: to, behavior: "smooth"});
    }
  },

  blank() {
    this.svg.setAttribute("hidden", "");
    this.strip.hidden = true;
    this.idle.hidden = false;
    this.lead.querySelectorAll(".fl-block.on").forEach((b) => b.classList.remove("on"));
    this.other.querySelectorAll(".fl-block.on").forEach((b) => b.classList.remove("on"));
    this.current = null;
  },
});
})();
