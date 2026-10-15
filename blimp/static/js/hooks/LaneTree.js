(() => {
// A git-log style lane tree: one row per node, a dot in a narrow lane
// column, the title beside it. The trunk (each node's first child) runs
// straight down; every other child branches into a fresh lane where it
// diverges. No d3 — a force layout of a few hundred nodes is an
// unreadable hairball, and this is lines and circles.
//
// Clicking a row fills the panel beside it. That panel is the point:
// a shape with no way to read the node under the dot tells you the
// graph exists but nothing about what it claims.
const COLOR = {
  goal: "#8a3324", option: "#b45309", decision: "#1e3a8a",
  action: "#166534", outcome: "#0891b2", observation: "#6b665e",
  revisit: "#7c2d92", spine: "#8a3324", beat: "#166534",
  thread: "#0891b2", question: "#7c2d92", note: "#9a948a",
};
const esc = (t) => String(t == null ? "" : t)
  .replace(/[&<>"]/g, (c) => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));

Blimp.hook("LaneTree", {
  mounted() { this.draw(); },
  updated() { this.draw(); },

  draw() {
    const data = JSON.parse(this.el.dataset.graph || "{}");
    const nodes = data.nodes || [];
    const edges = data.edges || [];
    const svg = this.el.querySelector("svg");
    if (!nodes.length) { svg.innerHTML = ""; return; }

    const byId = new Map(nodes.map((n) => [n.id, n]));
    this.byId = byId;
    this.edges = edges;

    // first edge into a node is its parent; the rest are cross-links
    const parentOf = new Map(), secondary = [];
    [...edges].sort((a, b) => a.id - b.id).forEach((e) => {
      if (!parentOf.has(e.to_node_id)) parentOf.set(e.to_node_id, e.from_node_id);
      else secondary.push(e);
    });

    const kids = new Map();
    nodes.forEach((n) => {
      const p = parentOf.get(n.id);
      if (p !== undefined) { if (!kids.has(p)) kids.set(p, []); kids.get(p).push(n.id); }
    });

    // A node's lane is how deep a branch it sits on, not the order it
    // was allocated in. The first child continues its parent's lane —
    // that is the trunk — and every other child opens one lane to the
    // right of it. Allocating a fresh lane per branch instead made the
    // tree walk off the right-hand side as a staircase; recycling
    // lanes flattened every branch back onto the trunk. Depth is the
    // thing a reader is actually looking for, and it is bounded by how
    // nested the argument is rather than by how long the draft is.
    const row = new Map(), lane = new Map();
    let r = 0;

    const walk = (startId, l) => {
      let id = startId;
      while (id != null) {
        if (row.has(id)) return;          // a cycle would spin here
        row.set(id, r++); lane.set(id, l);
        const cs = (kids.get(id) || []).filter((k) => !row.has(k));
        if (!cs.length) { id = null; }
        else { for (let i = 1; i < cs.length; i++) walk(cs[i], l + 1); id = cs[0]; }
      }
    };
    const roots = nodes.filter((n) => !parentOf.has(n.id));
    roots.forEach((n) => walk(n.id, 0));
    nodes.forEach((n) => { if (!row.has(n.id)) walk(n.id, 0); });

    const rowH = 21, laneW = 12, x0 = 12, gap = 16;
    const maxLane = Math.max(0, ...lane.values());
    const cap = Math.min(maxLane, 12);
    // clamped, so a deep lane can never be drawn past the gutter and
    // land on top of the label — which is exactly what it was doing
    const xOf = (l) => x0 + Math.min(l, cap) * laneW;
    const yOf = (id) => row.get(id) * rowH + 16;
    const labelX = x0 + cap * laneW + gap;
    const width = labelX + 640;
    const height = r * rowH + 28;
    const parts = [];

    secondary.forEach((e) => {
      if (!row.has(e.from_node_id) || !row.has(e.to_node_id)) return;
      const ax = xOf(lane.get(e.from_node_id)) - 5, ay = yOf(e.from_node_id);
      const bx = xOf(lane.get(e.to_node_id)) - 5, by = yOf(e.to_node_id);
      const mx = Math.min(ax, bx) - 10;
      parts.push(`<path d="M${ax},${ay} C${mx},${ay} ${mx},${by} ${bx},${by}" fill="none" stroke="#8a3324" stroke-opacity=".3" stroke-dasharray="1,3"/>`);
    });

    kids.forEach((cs, pid) => {
      if (!row.has(pid)) return;
      cs.forEach((cid) => {
        if (!row.has(cid)) return;
        const ax = xOf(lane.get(pid)), ay = yOf(pid);
        const bx = xOf(lane.get(cid)), by = yOf(cid);
        const stroke = COLOR[byId.get(cid)?.marginalia_type] || "#9a948a";
        const d = ax === bx
          ? `M${ax},${ay} L${bx},${by}`
          : `M${ax},${ay} C${ax},${(ay + by) / 2} ${bx},${(ay + by) / 2} ${bx},${by}`;
        parts.push(`<path d="${d}" fill="none" stroke="${stroke}" stroke-opacity=".45" stroke-width="1.5"/>`);
      });
    });

    nodes.forEach((n) => {
      if (!row.has(n.id)) return;
      const x = xOf(lane.get(n.id)), y = yOf(n.id);
      const c = COLOR[n.marginalia_type] || "#9a948a";
      const anchored = (() => { try { return JSON.parse(n.metadata_json).anchored; } catch { return false; } })();
      const label = n.title.length > 82 ? n.title.slice(0, 81) + "…" : n.title;
      parts.push(
        `<g class="gnode" data-id="${n.id}" style="cursor:pointer">` +
        `<rect x="0" y="${y - 10}" width="${width}" height="${rowH}" fill="transparent"/>` +
        `<circle cx="${x}" cy="${y}" r="3.6" fill="${anchored ? c : "none"}" stroke="${c}" stroke-width="1.5"/>` +
        `<text x="${labelX}" y="${y + 4}" font-size="12.5" fill="#1c1a17" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,Helvetica,Arial,sans-serif">${esc(label)}</text>` +
        `</g>`
      );
    });

    svg.setAttribute("width", width);
    svg.setAttribute("height", height);
    svg.innerHTML =
      `<style>.gnode:hover rect{fill:#f4f1ea}.gnode.sel rect{fill:#fdf2c9}</style>` + parts.join("");

    // Hovering previews, clicking keeps. Reading a graph means moving
    // down it; making someone click every row to find out what it
    // says turns reading into filing.
    svg.querySelectorAll(".gnode").forEach((g) => {
      const nodeId = Number(g.dataset.id);

      g.addEventListener("mouseenter", () => this.detail(nodeId, true));
      g.addEventListener("mouseleave", () => this.restore());

      g.addEventListener("click", () => {
        svg.querySelectorAll(".gnode.sel").forEach((o) => o.classList.remove("sel"));
        g.classList.add("sel");
        this.kept = nodeId;
        this.detail(nodeId, false);
      });
    });
  },

  // back to whatever was clicked, or to the empty state
  restore() {
    if (this.kept != null) return this.detail(this.kept, false);
    const panel = document.getElementById("graph-detail");
    if (panel && this.blank != null) panel.innerHTML = this.blank;
  },

  detail(id, previewing) {
    const panel = document.getElementById("graph-detail");
    if (!panel) return;
    if (this.blank == null) this.blank = panel.innerHTML;
    const n = this.byId.get(id);
    if (!n) return;
    let meta = {};
    try { meta = JSON.parse(n.metadata_json); } catch {}
    const c = COLOR[n.marginalia_type] || "#9a948a";

    const rel = (list, dir) => list.map((e) => {
      const other = this.byId.get(dir === "out" ? e.to_node_id : e.from_node_id);
      if (!other) return "";
      return `<div class="gd-edge">` +
        `<span class="gd-arrow">${dir === "out" ? "→" : "←"}</span>` +
        `<span><b>${esc(other.title)}</b>` +
        `<span class="gd-type">${esc(other.marginalia_type)}</span>` +
        (e.rationale ? `<em>${esc(e.rationale)}</em>` : "") +
        `</span></div>`;
    }).join("");

    const out = this.edges.filter((e) => e.from_node_id === id);
    const into = this.edges.filter((e) => e.to_node_id === id);

    panel.innerHTML =
      `<style>
         .gd h3{font-family:var(--mg-serif);font-size:1.02rem;line-height:1.3;margin:.35rem 0 .5rem}
         .gd .row{display:flex;gap:.35rem;flex-wrap:wrap;align-items:center}
         .gd .t{font-size:.6rem;letter-spacing:.09em;text-transform:uppercase;font-weight:600;
                border:1px solid ${c};color:${c};border-radius:2px;padding:.08rem .35rem}
         .gd .k{font-size:.6rem;letter-spacing:.12em;text-transform:uppercase;color:var(--mg-dim);
                font-weight:600;margin:1rem 0 .3rem}
         .gd p{font-size:.8rem;line-height:1.6;margin:0}
         .gd blockquote{font-family:var(--mg-serif);font-size:.88rem;color:var(--mg-dim);
                border-left:2px solid var(--mg-accent);padding-left:.6rem;margin:0}
         .gd-edge{display:flex;gap:.4rem;font-size:.76rem;line-height:1.45;margin:.45rem 0}
         .gd-arrow{color:var(--mg-dim)}
         .gd-edge b{font-weight:600}
         .gd-edge .gd-type{font-size:.58rem;letter-spacing:.08em;text-transform:uppercase;
                color:var(--mg-dim);margin-left:.35rem}
         .gd-edge em{display:block;color:var(--mg-dim);font-style:italic;margin-top:.1rem}
         .gd .peeking{font-size:.58rem;letter-spacing:.11em;text-transform:uppercase;
                color:var(--mg-dim);opacity:.75;margin-bottom:.55rem}
         .gd.previewing{opacity:.88}
       </style>
       <div class="gd${previewing ? " previewing" : ""}">
         ${previewing ? `<div class="peeking">previewing · click to keep</div>` : ""}
         <div class="row">
           <span class="t">${esc(n.marginalia_type)}</span>
           ${n.status && n.status !== "pending" ? `<span class="mg-badge">${esc(n.status)}</span>` : ""}
           ${meta.anchored ? `<span class="mg-badge">anchored</span>` : `<span class="mg-badge">unanchored</span>`}
         </div>
         <h3>${esc(n.title)}</h3>
         ${n.narrative ? `<div class="k">narrative</div><p>${esc(n.narrative)}</p>` : ""}
         ${n.section ? `<div class="k">section</div><p>${esc(n.section_ordinal)}. ${esc(n.section)}</p>` : ""}
         ${n.body ? `<div class="k">commentary</div><p>${esc(n.body)}</p>` : ""}
         ${n.quote ? `<div class="k">in your own words</div><blockquote>${esc(n.quote)}</blockquote>` : ""}
         ${into.length ? `<div class="k">follows from</div>${rel(into, "in")}` : ""}
         ${out.length ? `<div class="k">leads to</div>${rel(out, "out")}` : ""}
       </div>`;
  },
});
})();
