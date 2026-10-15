(() => {
// Follow the conversation only while the reader is already at the
// bottom. Yanking someone back down mid-scroll while they are reading
// an earlier answer is the single most irritating thing a chat can do.
Blimp.hook("StickToBottom", {
  mounted() {
    this.pinned = true;
    this.el.addEventListener("scroll", () => {
      const gap = this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight;
      this.pinned = gap < 80;
    });
    this.toBottom("auto");
  },
  updated() { if (this.pinned) this.toBottom("smooth"); },
  toBottom(behavior) {
    requestAnimationFrame(() => this.el.scrollTo({top: this.el.scrollHeight, behavior}));
  },
});
})();
