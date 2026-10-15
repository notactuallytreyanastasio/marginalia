(() => {
// The steering box grows with what is typed in it, up to a point.
//
// It was a one-line input, which is fine for "shorter" and wrong
// for the three-clause instruction people actually write: past
// the width of the box you are typing into a slot that shows you
// the last few words and hides the rest.
Blimp.hook("Steer", {
  mounted() {
    this.grow = () => {
      this.el.style.height = "auto";
      // capped, because this sits between the passage and the
      // candidates and should not push either off the screen
      this.el.style.height = Math.min(this.el.scrollHeight, 160) + "px";
    };

    this.onKey = (e) => {
      // Enter sends it; Shift+Enter is a newline, which is the
      // convention every chat box has taught everybody
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        this.el.form?.dispatchEvent(
          new Event("submit", {bubbles: true, cancelable: true})
        );
      }
    };

    this.el.addEventListener("input", this.grow);
    this.el.addEventListener("keydown", this.onKey);
    this.grow();
  },

  // phx-update="ignore" keeps what is half-typed through a patch,
  // so the height has to be re-measured here rather than on the
  // server's say-so
  updated() { this.grow(); },

  destroyed() {
    this.el.removeEventListener("input", this.grow);
    this.el.removeEventListener("keydown", this.onKey);
  },
});
})();
