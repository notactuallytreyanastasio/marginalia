(() => {
// Where to put the scroll when an answer lands.
//
// Sticking to the bottom is right for short replies and wrong for
// long ones: it drops the reader at the last line of something they
// have not read a word of, and they have to scroll *up* to find the
// beginning. So a reply taller than the panel is snapped to its own
// top instead, and held there — no auto-scrolling while they read.
//
// The hold is released the moment they reach the end of it. From
// then on the panel sticks to the bottom again, which is what you
// want once you are caught up.
Blimp.hook("StickDown", {
  mounted() {
    this.bottom();
    this.el.addEventListener("scroll", () => this.check(), {passive: true});
  },

  updated() {
    const last = this.el.querySelector(".lc-turn.assistant:last-child");

    if (last && last !== this.seen) {
      this.seen = last;
      const room = this.el.clientHeight - 24;

      if (last.offsetHeight > room) {
        // start them at the first line of it
        this.holding = last;
        this.el.scrollTop = this.topOf(last) - 8;
        return;
      }

      this.holding = null;
      return this.bottom();
    }

    // a turn being added while they are caught up
    if (!this.holding && this.near()) this.bottom();
  },

  // the reader has read to the end of the held reply, so let go
  check() {
    if (!this.holding) return;
    const end = this.topOf(this.holding) + this.holding.offsetHeight;
    if (this.el.scrollTop + this.el.clientHeight >= end - 8) this.holding = null;
  },

  topOf(el) {
    return (
      el.getBoundingClientRect().top -
      this.el.getBoundingClientRect().top +
      this.el.scrollTop
    );
  },

  near() {
    return this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight < 120;
  },

  bottom() {
    this.el.scrollTop = this.el.scrollHeight;
  },
});
})();
