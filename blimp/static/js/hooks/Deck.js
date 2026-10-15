(() => {
// One slot holding several notes of the same kind, one visible.
//
// Every card is in the DOM; this only moves the `on` class. No
// round trip to read the next note, and nothing to re-fetch when
// you flip back. The cards share a single grid cell, so the slot
// is as tall as the tallest of them and flipping never changes
// the height — which matters here more than it looks, because
// the rail is measured and a slot that grew would push every
// note below it off its own line.
Blimp.hook("Deck", {
  mounted() {
    this.at = 0;
    this.onClick = (e) => {
      const step = e.target.closest("[data-step]");
      if (!step) return;
      // it is inside the slot, and the slot's other job is to
      // open the chat on the note it is showing
      e.preventDefault();
      e.stopPropagation();
      this.go(this.at + Number(step.dataset.step));
    };
    this.el.addEventListener("click", this.onClick);

    // arrows, once the pager has been reached by keyboard
    this.onKey = (e) => {
      if (e.key === "ArrowLeft") this.go(this.at - 1);
      if (e.key === "ArrowRight") this.go(this.at + 1);
    };
    this.el.addEventListener("keydown", this.onKey);

    this.show();
  },

  // A patch can replace the cards — a note added, a note
  // superseded — so the index is re-applied rather than assumed,
  // and clamped in case the pile got shorter.
  updated() { this.show(); },

  destroyed() {
    this.el.removeEventListener("click", this.onClick);
    this.el.removeEventListener("keydown", this.onKey);
  },

  cards() { return [...this.el.querySelectorAll(".cards > .mg-note")]; },

  go(i) {
    const n = this.cards().length;
    if (!n) return;
    this.at = ((i % n) + n) % n;
    this.show();
  },

  show() {
    const cards = this.cards();
    if (!cards.length) return;
    this.at = Math.min(this.at, cards.length - 1);

    cards.forEach((c, i) => {
      const on = i === this.at;
      c.classList.toggle("on", on);
      // a hidden card is not a tab stop and is not read out
      c.setAttribute("aria-hidden", on ? "false" : "true");
      c.tabIndex = on ? 0 : -1;
    });

    const n = this.el.querySelector(".nav .n");
    if (n) n.textContent = `${this.at + 1} / ${cards.length}`;
  },
});
})();
