(() => {
// Three seconds a line, then out, swap, in. One line never rotates.
Blimp.hook("Rotate", {
  mounted() {
    this.lines = JSON.parse(this.el.dataset.lines || "[]");
    this.i = 0;
    if (this.lines.length < 2) return;
    this.timer = setInterval(() => {
      this.el.classList.add("out");
      this.swap = setTimeout(() => {
        this.i = (this.i + 1) % this.lines.length;
        this.el.textContent = this.lines[this.i];
        this.el.classList.remove("out");
      }, 320);
    }, 3000);
  },
  destroyed() {
    clearInterval(this.timer);
    clearTimeout(this.swap);
  },
});
})();
