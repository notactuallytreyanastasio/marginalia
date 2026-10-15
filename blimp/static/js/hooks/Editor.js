(() => {
// The paragraph's markdown, in place. Not a rich text editor: the
// page is rendered from this source and every note is anchored into
// it, so round-tripping HTML back to markdown would quietly move
// every anchor in the section.
Blimp.hook("Editor", {
  mounted() {
    const ta = this.el.querySelector("textarea");
    if (!ta) return;

    const grow = () => {
      ta.style.height = "auto";
      ta.style.height = ta.scrollHeight + "px";
    };
    grow();
    ta.addEventListener("input", grow);

    ta.focus();
    ta.setSelectionRange(ta.value.length, ta.value.length);

    ta.addEventListener("keydown", (e) => {
      if (e.key === "Escape") {
        e.preventDefault();
        this.pushEvent("cancel_edit", {});
      }
      if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
        e.preventDefault();
        this.el.dispatchEvent(new Event("submit", {bubbles: true, cancelable: true}));
      }
    });
  },
});
})();
