(() => {
// The link is the permission, so handing it over has to be one click.
Blimp.hook("Share", {
  mounted() {
    this.el.addEventListener("click", async () => {
      const was = this.el.textContent;
      try {
        await navigator.clipboard.writeText(this.el.dataset.url);
        this.el.textContent = "Copied";
      } catch {
        // clipboard blocked (insecure origin, denied permission):
        // select it instead so they can copy it by hand
        window.prompt("Copy this link", this.el.dataset.url);
        this.el.textContent = was;
        return;
      }
      setTimeout(() => (this.el.textContent = was), 1400);
    });
  },
});
})();
