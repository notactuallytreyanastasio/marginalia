(() => {
// A member per row, and arcs between the pairs a claim rests on.
//
// While the read runs, the arcs shown are *candidates*: every pair of
// members, tried one at a time. That is not decoration — it is the
// question being asked, which is whether anything holds across two or
// more of these. When the answer lands the candidates stop and the
// pairs that actually held are drawn in, so the waiting state and the
// result are the same picture at two moments.
const ROW = 26, PAD = 12, GUT = 22;

Blimp.hook("Weave", {
  mounted() { this.draw(); },
  updated() { this.draw(); },
  destroyed() { this.stop(); },

  stop() {
    cancelAnimationFrame(this.frame);
    clearTimeout(this.timer);
    this.frame = this.timer = null;
  },

  draw() {
    this.stop();
    const members = JSON.parse(this.el.dataset.members || "[]");
    const links = JSON.parse(this.el.dataset.links || "[]");
    const reading = this.el.dataset.status === "reading";
    const svg = this.el.querySelector("svg");
    if (members.length < 2) { svg.innerHTML = ""; this.el.hidden = true; return; }

    const h = PAD * 2 + members.length * ROW;
    const w = 280;
    svg.setAttribute("viewBox", `0 0 ${w} ${h}`);
    svg.setAttribute("height", h);
    const y = (n) => PAD + (n - 1) * ROW + ROW / 2;

    const rows = members.map((m) => `
      <line class="cw-rule" x1="${GUT}" y1="${y(m.n)}" x2="${w - 8}" y2="${y(m.n)}"></line>
      <circle class="cw-dot" cx="${GUT}" cy="${y(m.n)}" r="3.2"></circle>
      <text class="cw-lbl" x="${GUT - 10}" y="${y(m.n) + 3.5}">${m.n}</text>`).join("");

    // The `d` alone, so both kinds of arc keep their class name as a
    // literal in the markup they build. A class that only exists as a
    // function argument is one nothing can check for.
    const curve = (a, b) => {
      const y1 = y(a), y2 = y(b);
      const bulge = Math.min(46, 14 + Math.abs(y1 - y2) * 0.42);
      return `M ${GUT} ${y1} C ${GUT + bulge} ${y1}, ${GUT + bulge} ${y2}, ${GUT} ${y2}`;
    };

    svg.innerHTML = rows + links.map((l) =>
      `<path class="cw-arc k-${l.kind}" fill="none" d="${curve(l.a, l.b)}"></path>`
    ).join("");

    // draw the settled arcs in, once
    svg.querySelectorAll(".cw-arc").forEach((p, i) => {
      const len = p.getTotalLength();
      p.style.strokeDasharray = len;
      p.style.strokeDashoffset = len;
      p.style.animation = `cw-draw .7s ease ${0.1 + i * 0.09}s forwards`;
    });

    if (reading) this.tryPairs(svg, members, curve);
  },

  // Every pair, in order, on a loop. The order is fixed rather than
  // random so two people watching the same folder see the same thing.
  tryPairs(svg, members, curve) {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const pairs = [];
    for (let i = 0; i < members.length; i++)
      for (let j = i + 1; j < members.length; j++)
        pairs.push([members[i].n, members[j].n]);

    let k = 0;
    const step = () => {
      svg.querySelectorAll(".cw-try").forEach((n) => n.remove());
      const [a, b] = pairs[k % pairs.length];
      svg.insertAdjacentHTML(
        "beforeend",
        `<path class="cw-try" fill="none" d="${curve(a, b)}"></path>`
      );
      const p = svg.querySelector(".cw-try");
      const len = p.getTotalLength();
      p.style.setProperty("--len", len);
      p.style.strokeDasharray = len;
      p.style.strokeDashoffset = len;
      p.style.animation = "cw-try 1.15s ease-in-out forwards";
      [a, b].forEach((n) => {
        const dot = svg.querySelectorAll(".cw-dot")[n - 1];
        if (dot) { dot.classList.remove("lit"); void dot.offsetWidth; dot.classList.add("lit"); }
      });
      k++;
      this.timer = setTimeout(step, 1250);
    };
    step();
  },
});
})();
