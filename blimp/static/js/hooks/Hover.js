(() => {
// Hover to see a candidate in the line it would replace; the
// pointer leaving puts the line back. Debounced on the way out so
// moving between two candidates does not flicker the paragraph.
Blimp.hook("Hover", {
  mounted() {
    this.el.addEventListener("mouseover", (e) => {
      const row = e.target.closest(".mg-rw");
      if (!row) return;
      clearTimeout(this.out);
      if (row.dataset.i !== this.showing) {
        this.showing = row.dataset.i;
        this.pushEvent("preview_rewrite", {i: row.dataset.i});
      }
    });

    this.el.addEventListener("mouseleave", () => {
      clearTimeout(this.out);
      this.out = setTimeout(() => {
        this.showing = null;
        this.pushEvent("clear_preview", {});
      }, 80);
    });
  },
  destroyed() { clearTimeout(this.out); },
});
})();
