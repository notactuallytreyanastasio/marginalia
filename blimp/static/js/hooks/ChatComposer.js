(() => {
// Enter sends, Shift+Enter writes a newline, and the box grows with
// the question instead of hiding it one line at a time.
Blimp.hook("ChatComposer", {
  mounted() {
    const ta = this.el.querySelector("textarea");
    if (!ta) return;
    const MIN = 120, MAX = 352;
    const grow = () => {
      ta.style.height = "auto";
      ta.style.height = Math.max(MIN, Math.min(ta.scrollHeight, MAX)) + "px";
    };
    ta.addEventListener("input", grow);
    ta.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && !e.shiftKey && !e.isComposing) {
        e.preventDefault();
        if (ta.value.trim()) this.el.dispatchEvent(new Event("submit", {bubbles: true, cancelable: true}));
      }
    });
    this.handleEvent("chat:clear", () => { ta.value = ""; grow(); ta.focus(); });
    ta.focus();
  },
});
})();
