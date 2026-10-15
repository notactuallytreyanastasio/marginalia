(() => {
// Click anywhere outside the panel and it puts itself away. The
// conversation is server-side, so this loses nothing — reopening
// comes back to the same place.
Blimp.hook("LinkChat", {
  mounted() {
    this.away = (e) => {
      if (!this.el.querySelector(".lc-panel")) return;
      if (this.el.contains(e.target)) return;
      this.pushEvent("close_chat", {});
    };
    this.esc = (e) => e.key === "Escape" && this.pushEvent("close_chat", {});
    document.addEventListener("mousedown", this.away);
    document.addEventListener("keydown", this.esc);
  },

  updated() {
    // focus the box when the panel has just appeared
    const box = this.el.querySelector(".lc-foot textarea");
    if (box && !this.was) box.focus();
    this.was = !!this.el.querySelector(".lc-panel");
  },

  destroyed() {
    document.removeEventListener("mousedown", this.away);
    document.removeEventListener("keydown", this.esc);
  },
});
})();
