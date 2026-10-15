(() => {
// Notes arrive as you reach the paragraph they annotate, and the worked
// examples play their turns in sequence once they're on screen. Both are
// one-shot: re-animating on every scroll past would be nauseating.
Blimp.hook("Reveal", {
  mounted() {
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const targets = this.el.querySelectorAll("[data-reveal], [data-demo]");

    if (reduce || !("IntersectionObserver" in window)) return;

    // Only now does anything hide. Without JS, or before this runs, the
    // page is fully readable — a landing page that needs JS to show its
    // own copy is a landing page that sometimes shows nothing.
    this.el.classList.add("reveal-ready");

    this.io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("in");
          if (entry.target.hasAttribute("data-demo")) this.play(entry.target);
          this.io.unobserve(entry.target);
        });
      },
      // fire a little before the top edge so the note is already there
      // by the time the eye arrives
      { rootMargin: "0px 0px -12% 0px", threshold: 0.15 }
    );

    targets.forEach((el) => this.io.observe(el));
  },

  // A demo is markup that already says what it means; the steps only
  // control WHEN each part of it appears, so the whole thing is legible
  // with the script dead or with motion turned down — the final frame is
  // the default state and `reveal-ready` is what hides it.
  play(demo) {
    const gap = parseInt(demo.dataset.interval || "650", 10);
    const steps = [...demo.querySelectorAll("[data-step]")].sort(
      (a, b) => Number(a.dataset.step) - Number(b.dataset.step)
    );

    this.timers = this.timers || [];

    steps.forEach((step, i) => {
      this.timers.push(
        setTimeout(() => step.classList.add("on"), gap * (i + 1))
      );
    });
  },

  destroyed() {
    if (this.io) this.io.disconnect();
    (this.timers || []).forEach(clearTimeout);
  },
});
})();
