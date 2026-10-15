(() => {
// Native HTML5 drag and drop, delegated from the tree container so it
// survives every re-render LiveView does underneath it. No library:
// this is dragstart, dragover, drop, and the work is in deciding what
// is under the cursor.
//
// The one real rule is that a folder cannot be dropped into its own
// subtree. Because a folder's children are rendered *inside* its
// element, that rule is just `dragged.contains(target)` — the illegal
// targets are exactly the ones the dragged element encloses. The
// server checks it again by walking parent_id, since this is a fact
// about the tree rather than about the mouse.
Blimp.hook("Tree", {
  mounted() {
    this.drag = null;

    this.on("dragstart", (e) => {
      const row = e.target.closest("[data-drag-id]");
      if (!row || !this.el.contains(row)) return;
      this.drag = {
        el: row,
        kind: row.dataset.dragKind,
        id: row.dataset.dragId,
      };
      row.classList.add("is-dragging");
      e.dataTransfer.effectAllowed = "move";
      // Firefox will not start a drag at all unless the payload is set.
      e.dataTransfer.setData("text/plain", row.dataset.dragId);
    });

    this.on("dragend", () => this.clear());

    // dragover is the only place the highlight is decided. A
    // dragleave handler is the obvious way to turn it off and the
    // wrong one: leave fires every time the cursor crosses into a
    // child of the row it is already over, so the row you are aiming
    // at strobes while you hold still.
    this.on("dragover", (e) => {
      const target = this.target(e);
      if (!target) return this.unlight();
      e.preventDefault();
      e.dataTransfer.dropEffect = "move";
      if (target !== this.lit) {
        this.unlight();
        this.lit = target;
        target.classList.add("is-over");
      }
    });

    this.on("drop", (e) => {
      const target = this.target(e);
      if (!target) return this.clear();
      e.preventDefault();
      const into = target.dataset.dropId;
      const drag = this.drag;
      this.clear();
      // Dropping something back where it already was is not a move.
      if (drag.kind === "folder" && into === drag.id) return;
      this.pushEvent("move", {kind: drag.kind, id: drag.id, into: into});
    });
  },

  destroyed() { this.clear(); },

  on(name, fn) { this.el.addEventListener(name, fn); },

  // The drop zone under the cursor, or null if this drop is illegal.
  target(e) {
    if (!this.drag) return null;
    const zone = e.target.closest("[data-drop-id]");
    if (!zone || !this.el.contains(zone)) return null;
    if (this.drag.el.contains(zone)) return null;
    return zone;
  },

  unlight() {
    if (this.lit) this.lit.classList.remove("is-over");
    this.lit = null;
  },

  clear() {
    this.unlight();
    if (this.drag) this.drag.el.classList.remove("is-dragging");
    this.drag = null;
  },
});
})();
