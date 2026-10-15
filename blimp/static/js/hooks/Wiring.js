(() => {
// Two columns of real nodes, and arcs tried between them. Nothing
// here is a result — see the note under it — it is the shape of the
// work, drawn while the work happens.
Blimp.hook("Wiring", {
  mounted() {
    this.a = JSON.parse(this.el.dataset.a || "[]");
    this.b = JSON.parse(this.el.dataset.b || "[]");
    this.svg = this.el.querySelector(".lw-svg");
    this.arcs = this.svg.querySelector(".arcs");
    this.dots = this.svg.querySelector(".dots");
    this.now = {l: this.el.querySelector(".lw-now .l"), r: this.el.querySelector(".lw-now .r")};

    if (!this.a.length || !this.b.length) return;
    // the dots are already on the page; motion is all this adds
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    this.tick = setInterval(() => this.tryPair(), 900);
    this.tryPair();
  },

  destroyed() { clearInterval(this.tick); },

  // mirrors y/2 in the component — the dots are placed server-side
  // and the arcs have to arrive at the same coordinates
  y(i, n) { return 30 + (i * (300 / Math.max(n - 1, 1))); },

  tryPair() {
    const ns = "http://www.w3.org/2000/svg";
    const i = Math.floor(Math.random() * this.a.length);
    const j = Math.floor(Math.random() * this.b.length);
    const y1 = this.y(i, this.a.length);
    const y2 = this.y(j, this.b.length);

    const path = document.createElementNS(ns, "path");
    path.setAttribute("d", `M 90 ${y1} C 300 ${y1}, 380 ${y2}, 590 ${y2}`);
    path.setAttribute("class", "arc");
    this.arcs.appendChild(path);

    // draw it on, hold, fade it out — then take it away entirely, so
    // nothing accumulates that could be mistaken for a result
    const len = path.getTotalLength();
    path.style.strokeDasharray = len;
    path.style.strokeDashoffset = len;
    path.getBoundingClientRect();
    path.style.transition = "stroke-dashoffset .7s ease-out, opacity .5s ease-in .9s";
    path.style.strokeDashoffset = 0;
    path.style.opacity = 0;
    setTimeout(() => path.remove(), 1800);

    this.lightUp("a", i);
    this.lightUp("b", j);
    this.now.l.textContent = this.a[i];
    this.now.r.textContent = this.b[j];
  },

  lightUp(side, i) {
    const dot = this.dots.querySelector(`circle[data-side="${side}"][data-i="${i}"]`);
    if (!dot) return;
    dot.classList.add("lit");
    setTimeout(() => dot.classList.remove("lit"), 1200);
  },
});
})();
