(() => {
// Counts up from when the read started. Server-side ticking would mean
// a message a second per viewer to render a number nobody acts on.
Blimp.hook("Clock", {
  mounted() { this.tick(); this.t = setInterval(() => this.tick(), 1000); },
  destroyed() { clearInterval(this.t); },
  tick() {
    const since = Number(this.el.dataset.since);
    if (!since) return;
    const s = Math.max(0, Math.floor(Date.now() / 1000) - since);
    this.el.textContent = Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
  },
});
})();
