(() => {
// Enter sends; shift-Enter is a newline. The form said "Enter to
// send" and named this hook, and the hook was never written — so
// LiveView threw `unknown hook` on the client, the binding for
// the form never attached, and the panel opened, took typing and
// sent nothing. Server-side tests cannot see that: they do not
// run the hooks.
Blimp.hook("LinkChatComposer", {
  mounted() {
    this.box = this.el.querySelector("textarea");
    if (!this.box) return;

    this.onKey = (e) => {
      if (e.key !== "Enter" || e.shiftKey || e.isComposing) return;
      e.preventDefault();
      if (this.box.value.trim() === "") return;
      this.el.dispatchEvent(new Event("submit", {bubbles: true, cancelable: true}));
    };

    // two rows is right for a question and wrong for a paragraph
    this.grow = () => {
      this.box.style.height = "auto";
      this.box.style.height = Math.min(this.box.scrollHeight, 160) + "px";
    };

    this.box.addEventListener("keydown", this.onKey);
    this.box.addEventListener("input", this.grow);
    this.box.focus();
  },

  updated() {
    // the textarea is cleared by the server on send; put the
    // cursor back where someone would carry on typing
    if (this.box && !this.box.disabled && document.activeElement !== this.box) {
      this.box.style.height = "auto";
    }
  },

  destroyed() {
    if (!this.box) return;
    this.box.removeEventListener("keydown", this.onKey);
    this.box.removeEventListener("input", this.grow);
  },
});
})();
