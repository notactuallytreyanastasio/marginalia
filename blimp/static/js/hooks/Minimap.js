(() => {
// Open on click, and follow the reader down the page so the block
// beside where they are is lit. Kept client-side: which heading is
// on screen changes every few hundred milliseconds and is nobody's
// business but the browser's.
Blimp.hook("Minimap", {
  mounted() {
    this.links = [...this.el.querySelectorAll("a[data-target]")];
    this.rows = this.links.map((a) => a.parentElement);
    this.ticks = [...this.el.querySelectorAll(".mg-map-rail .t")];
    this.rail = this.el.querySelector(".mg-map-rail");

    this.rail.addEventListener("click", () => {
      const open = this.el.classList.toggle("open");
      this.rail.setAttribute("aria-expanded", open ? "true" : "false");
    });

    this.links.forEach((a, i) => {
      a.addEventListener("click", (e) => {
        e.preventDefault();
        const el = document.getElementById(a.dataset.target);
        if (el) el.scrollIntoView({behavior: "smooth", block: "start"});
        this.close();
        this.mark(i);
      });
    });

    // a click anywhere else closes it
    this.away = (e) => { if (!this.el.contains(e.target)) this.close(); };
    this.esc = (e) => { if (e.key === "Escape") this.close(); };
    document.addEventListener("click", this.away);
    document.addEventListener("keydown", this.esc);

    this.follow();
  },

  destroyed() {
    document.removeEventListener("click", this.away);
    document.removeEventListener("keydown", this.esc);
    this.io?.disconnect();
  },

  close() {
    this.el.classList.remove("open");
    this.rail.setAttribute("aria-expanded", "false");
  },

  mark(i) {
    this.ticks.forEach((t, j) => t.classList.toggle("on", j === i));
    this.rows.forEach((r, j) => r.classList.toggle("on", j === i));
  },

  follow() {
    const targets = this.links
      .map((a) => document.getElementById(a.dataset.target))
      .filter(Boolean);
    if (!targets.length) return;

    this.io = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          const i = targets.indexOf(entry.target);
          if (i >= 0) this.mark(i);
        }
      },
      // a band across the top: whatever has most recently passed it
      // is what the reader is in
      {rootMargin: "-10% 0px -80% 0px"}
    );

    targets.forEach((t) => this.io.observe(t));
  },
});
})();
