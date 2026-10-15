(() => {
// Two layouts, one set of notes.
//
// Wide: each note sits level with its own highlight, measured and
// stacked so nothing overlaps. Grid rows cannot do this — they either
// tear holes in the prose or drop the alignment.
//
// Narrow, which is what the chat drawer leaves: there is no margin,
// and a rail squeezed into what remains is worse than none. So the
// notes fold back into the text. The highlight becomes the whole
// affordance — hover peeks, click pins. Pinning matters because
// reading a note and then going to write about it should not require
// holding the mouse still.
Blimp.hook("MarginNotes", {
  mounted() {
    this.pinned = new Set();
    this.showing = new Map();
    this.layout();
    this.watch();
  },
  updated() {
    // a morph may have replaced the highlights: point the open peeks
    // and pins at the current nodes, and drop the ones that are gone
    [...this.showing.keys()].forEach((ref) => {
      const mark = this.el.querySelector(`#anchor-${CSS.escape(ref)}`);
      if (mark) this.showing.set(ref, mark);
      else { this.showing.delete(ref); this.pinned.delete(ref); }
    });
    this.pinned.forEach((ref) =>
      this.el.querySelector(`#anchor-${CSS.escape(ref)}`)?.classList.add("pinned"));
    this.layout();
  },
  destroyed() {
    this.el.removeEventListener("mouseover", this.onOver);
    this.el.removeEventListener("mouseout", this.onOut);
    this.el.removeEventListener("click", this.onMarkClick);
    this.ro?.disconnect();
    document.removeEventListener("click", this.onAway);
    window.removeEventListener("scroll", this.onScroll, true);
    window.removeEventListener("resize", this.onScroll);
  },

  collapsed() { return this.el.classList.contains("collapsed"); },

  slotsFor(ref) {
    return [...this.el.querySelectorAll(`.mg-note-slot[data-anchor="${CSS.escape(ref)}"]`)];
  },

  watch() {
    this.ro = new ResizeObserver(() => this.layout());
    this.ro.observe(this.el);

    // Delegated on this.el, so notes and highlights the server adds or
    // replaces later are covered without rebinding. mouseenter/leave do
    // not bubble; mouseover/out do, so enter/leave is rebuilt from
    // relatedTarget.
    const markOf = (t) => t.closest?.(".mg-read-body mark[id]");
    const slotOf = (t) => t.closest?.(".mg-note-slot");
    const anchorMark = (slot) => {
      const id = slot.dataset.anchor;
      return id && this.el.querySelector(`#anchor-${CSS.escape(id)}`);
    };

    this.onOver = (e) => {
      const slot = slotOf(e.target);
      if (slot && !slot.contains(e.relatedTarget)) anchorMark(slot)?.classList.add("lit");
      const mark = markOf(e.target);
      if (mark && !mark.contains(e.relatedTarget) && this.collapsed())
        this.peek(mark.id.replace(/^anchor-/, ""), mark);
    };
    this.onOut = (e) => {
      const slot = slotOf(e.target);
      if (slot && !slot.contains(e.relatedTarget)) anchorMark(slot)?.classList.remove("lit");
      const mark = markOf(e.target);
      if (mark && !mark.contains(e.relatedTarget) && this.collapsed())
        this.unpeek(mark.id.replace(/^anchor-/, ""));
    };
    this.onMarkClick = (e) => {
      const mark = markOf(e.target);
      if (!mark || !this.collapsed()) return;
      const ref = mark.id.replace(/^anchor-/, "");
      e.stopPropagation();
      if (this.pinned.has(ref)) { this.pinned.delete(ref); this.unpeek(ref); }
      else { this.pinned.add(ref); this.peek(ref, mark); }
      mark.classList.toggle("pinned", this.pinned.has(ref));
    };
    this.el.addEventListener("mouseover", this.onOver);
    this.el.addEventListener("mouseout", this.onOut);
    this.el.addEventListener("click", this.onMarkClick);

    // a click anywhere else lets go of everything pinned
    this.onAway = (e) => {
      if (!this.collapsed()) return;
      if (e.target.closest(".mg-note-slot") || e.target.closest("mark[id]")) return;
      [...this.pinned].forEach((ref) => { this.pinned.delete(ref); this.unpeek(ref); });
      this.el.querySelectorAll("mark.pinned").forEach((m) => m.classList.remove("pinned"));
    };
    document.addEventListener("click", this.onAway);

    // follow the text: capture phase, so a scroll inside the drawer
    // or any other scrolling ancestor counts too
    let queued = false;
    this.onScroll = () => {
      if (queued || !this.showing.size) return;
      queued = true;
      requestAnimationFrame(() => { queued = false; this.reposition(); });
    };
    window.addEventListener("scroll", this.onScroll, true);
    window.addEventListener("resize", this.onScroll);
  },

  peek(ref, mark) {
    this.showing.set(ref, mark);
    this.slotsFor(ref).forEach((slot) => slot.classList.add("peek"));
    this.reposition();
  },

  unpeek(ref) {
    if (this.pinned.has(ref)) return;
    this.showing.delete(ref);
    this.slotsFor(ref).forEach((slot) => {
      slot.classList.remove("peek");
      slot.style.left = "";
      slot.style.top = "";
      slot.style.removeProperty("--caret");
    });
  },

  // Fixed positioning takes viewport coordinates, and the page scrolls
  // under them — so the note has to be put back against its highlight
  // on every scroll, or it is left behind the moment you move. This
  // runs on scroll and resize, rAF-throttled.
  // The notes on one highlight are laid out as a stack, not as
  // independent boxes. Clamping each one to the viewport separately
  // collapsed them onto the same `top` whenever the group did not
  // fit, so two notes landed on top of each other — the group is
  // measured and clamped once, then each note is placed from there.
  reposition() {
    const GAP = 8;

    this.showing.forEach((mark, ref) => {
      const r = mark.getBoundingClientRect();
      const slots = this.slotsFor(ref);
      if (!slots.length) return;

      // the highlight has scrolled away: take the note with it,
      // unless it is pinned
      const gone = r.bottom < 8 || r.top > window.innerHeight - 8;
      if (gone && !this.pinned.has(ref)) return this.unpeek(ref);

      const heights = slots.map((s) => s.offsetHeight);
      const total = heights.reduce((a, h) => a + h, 0) + GAP * (slots.length - 1);

      // below the line by default, above it when there is no room,
      // and clamped as one block so the stack never folds together
      const below = r.bottom + 10;
      const above = below + total > window.innerHeight - 12;
      let top = above ? r.top - total - 10 : below;
      top = Math.max(8, Math.min(top, window.innerHeight - total - 8));

      const width = slots[0].offsetWidth;
      const left = Math.max(12, Math.min(r.left, window.innerWidth - 12 - width));
      // the caret points back at the start of the span it is about
      const caret = Math.max(14, Math.min(r.left - left + 10, width - 20));

      slots.forEach((slot, i) => {
        slot.style.left = `${left}px`;
        slot.style.top = `${top}px`;
        slot.style.setProperty("--caret", `${caret}px`);
        slot.style.zIndex = `${55 + i}`;
        slot.classList.toggle("flipped", above);
        // only the note nearest the line gets the pointer
        slot.classList.toggle("tailed", above ? i === slots.length - 1 : i === 0);
        top += heights[i] + GAP;
      });
    });
  },

  layout() {
    const rail = this.el.querySelector(".mg-read-rail");
    if (!rail) return;

    // collapsed: the notes live in the highlights, nothing to place
    if (this.collapsed()) {
      rail.classList.remove("measured");
      rail.style.height = "";
      this.unshove();
      this.el.querySelectorAll(".mg-note-slot").forEach((s) => {
        if (!s.classList.contains("peek")) s.style.top = "";
      });
      return;
    }

    // back to the margin: drop anything left floating
    this.el.querySelectorAll(".mg-note-slot.peek").forEach((s) => {
      s.classList.remove("peek");
      s.style.left = "";
    });
    this.el.querySelectorAll("mark.pinned").forEach((m) => m.classList.remove("pinned"));
    this.pinned.clear();
    this.showing.clear();

    // one column is too narrow for a margin: fall back to flow
    if (getComputedStyle(this.el).gridTemplateColumns.split(" ").length < 3) {
      rail.classList.remove("measured");
      rail.style.height = "";
      this.unshove();
      this.el.querySelectorAll(".mg-note-slot").forEach((s) => (s.style.top = ""));
      return;
    }

    rail.classList.add("measured");
    const railTop = rail.getBoundingClientRect().top;
    let y = 0;

    this.el.querySelectorAll(".mg-note-slot").forEach((slot) => {
      const id = slot.dataset.anchor;
      const mark = id && this.el.querySelector(`#anchor-${CSS.escape(id)}`);
      const wanted = mark ? mark.getBoundingClientRect().top - railTop : y;
      const top = Math.max(wanted, y);
      slot.style.top = `${top}px`;
      y = top + slot.offsetHeight + 10;
    });

    rail.style.height = `${y}px`;
    this.shove(rail, railTop);
  },

  // An applied diff is as wide as all three columns and sits on
  // top of the rail, so the notes level with it are buried — and
  // the ones it buries are exactly the notes about the paragraph
  // that just changed. They move out past the prose, on the other
  // side, and come back when the diff is dismissed.
  //
  // There is less room out there than the note needs. The page is
  // 66ch of prose, a 3rem gutter and a 34ch rail, centred: at
  // 1512px that leaves 232px of margin against a 327px rail, and
  // on the 1000px-wide window this was reported from, 115px. So
  // the note goes as far left as the window allows and floats
  // over the left edge of the diff for the rest. Covering the
  // first few characters of a diff that is 100ch wide costs less
  // than burying the note about the paragraph that just changed,
  // which is what happens today.
  shove(rail, railTop) {
    const diff = this.el.querySelector(".mg-applied");
    if (!diff) return this.unshove();

    const slots = [...this.el.querySelectorAll(".mg-note-slot")];
    const body = this.el.querySelector(".mg-read-body");
    if (!slots.length || !body) return this.unshove();

    const d = diff.getBoundingClientRect();
    const b = body.getBoundingClientRect();
    const r = rail.getBoundingClientRect();

    const EDGE = 14;
    const TAIL = 18;
    // how close a note may come to the diff without being moved
    const CLEAR = 20;

    // Clear of the contents rail, which is fixed furniture down
    // the left of the window and would otherwise be drawn over
    // the first few words of every shoved note.
    const map = document.querySelector(".mg-map");
    const edge = Math.max(EDGE, map ? map.getBoundingClientRect().right + 10 : EDGE);

    const width = slots[0].offsetWidth;

    // in the rail's own coordinates, since that is what `left`
    // on an absolutely positioned slot is measured from
    const to = Math.max(edge, b.left - TAIL - width) - r.left;

    const band = {top: d.top - railTop, bottom: d.bottom - railTop};
    let floor = -Infinity;

    slots.forEach((slot) => {
      let top = parseFloat(slot.style.top) || 0;
      const high = slot.offsetHeight;

      // A third of the note, not a pixel of it. A card whose last
      // line grazes the top of the diff is still readable, and
      // sending it across the page for that is a worse jolt than
      // the overlap.
      const over = Math.min(top + high, band.bottom) - Math.max(top, band.top);
      const hits = over > high / 3;

      slot.classList.toggle("shoved", hits);
      // pinned in pixels rather than left to `right: auto`, or the
      // bubble collapses to its content width as it crosses
      slot.style.width = hits ? `${width}px` : "";
      slot.style.left = hits ? `${to}px` : "";

      // The near miss, which is the common one and the one that
      // looks like a bug: a card comes to rest with its last line
      // four pixels under the diff's top edge. Not worth sending
      // across the page, so it is moved clear the short way —
      // away from the diff, never into the card above it.
      if (!hits && top + high > band.top - CLEAR && top < band.bottom + CLEAR) {
        const above = top + high / 2 < (band.top + band.bottom) / 2;
        const want = above ? band.top - CLEAR - high : band.bottom + CLEAR;

        if (!above || want >= floor + 10) {
          top = want;
          slot.style.top = `${top}px`;
        }
      }

      floor = top + high;
    });
  },

  unshove() {
    this.el.querySelectorAll(".mg-note-slot.shoved").forEach((s) => {
      s.classList.remove("shoved");
      s.style.left = "";
      s.style.width = "";
    });
  },
});
})();
