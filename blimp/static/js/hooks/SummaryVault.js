(() => {
// The server stores one summary per section. Running it again overwrites
// that row, and the text that was there is gone — so this keeps the last
// few in the browser that produced them, and offers them back.
//
// It is a safety net, not a backup: localStorage is per-browser and
// per-device, it can be cleared by the person or the browser, and every
// read and write here is wrapped because in a private window the
// accessor itself throws. Nothing on the page depends on it working.
const KEY = (k) => `mg:sum:${k}`;
const KEEP = 6;

const read = (k) => {
  try {
    return JSON.parse(localStorage.getItem(KEY(k)) || "[]");
  } catch (_) {
    return [];
  }
};

const write = (k, list) => {
  try {
    localStorage.setItem(KEY(k), JSON.stringify(list.slice(0, KEEP)));
  } catch (_) {
    // quota, or storage disabled. The page is unaffected.
  }
};

Blimp.hook("SummaryVault", {
  mounted() { this.sweep(); },
  updated() { this.sweep(); },

  sweep() {
    this.el.querySelectorAll("[data-sum-key]").forEach((el) => {
      const key = el.dataset.sumKey;
      const text = el.dataset.sumText || "";
      if (!key || !text) return;

      const list = read(key);

      // Only when it actually changed. A re-render of the same summary
      // must not fill the vault with copies of one thing.
      if (!list.length || list[0].s !== text) {
        list.unshift({ s: text, at: el.dataset.sumAt || new Date().toISOString() });
        write(key, list);
      }

      this.render(key, list);
    });
  },

  render(key, list) {
    const ordinal = key.split(":").pop();
    const box = document.getElementById(`sumvault-${ordinal}`);
    if (!box) return;

    const older = list.slice(1);
    if (!older.length) { box.innerHTML = ""; return; }

    const d = document.createElement("details");
    const sum = document.createElement("summary");
    sum.textContent = `${older.length} earlier ${older.length === 1 ? "version" : "versions"} of this summary, kept in this browser`;
    d.appendChild(sum);

    older.forEach((v) => {
      const p = document.createElement("p");
      const when = document.createElement("span");
      when.className = "when";
      when.textContent = (v.at || "").slice(0, 16).replace("T", " ");
      p.appendChild(when);
      p.appendChild(document.createTextNode(v.s));
      d.appendChild(p);
    });

    box.replaceChildren(d);
  },
});
})();
