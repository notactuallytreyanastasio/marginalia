// Tests for blimp.js and the ported hooks. Run: node blimp/test/js/run.mjs
// Needs jsdom: found globally, via $JSDOM_DIR, or installed once into a cache
// directory under the OS temp dir (npm install jsdom).
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createRequire } from "node:module";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const js = path.resolve(here, "../../static/js");

function loadJsdom() {
  const tries = [process.env.JSDOM_DIR, path.join(os.tmpdir(), "blimp-jsdom")].filter(Boolean);
  try { return createRequire(import.meta.url)("jsdom"); } catch (_) {}
  for (const d of tries) {
    try { return createRequire(path.join(d, "x.js"))("jsdom"); } catch (_) {}
  }
  const cache = path.join(os.tmpdir(), "blimp-jsdom");
  fs.mkdirSync(cache, { recursive: true });
  console.log(`installing jsdom into ${cache} ...`);
  execFileSync("npm", ["install", "--silent", "--prefix", cache, "jsdom"], { stdio: "inherit" });
  return createRequire(path.join(cache, "x.js"))("jsdom");
}
const { JSDOM } = loadJsdom();

const read = (f) => fs.readFileSync(path.join(js, f), "utf8");
const blimpSrc = read("blimp.js");
const hookFiles = fs.readdirSync(path.join(js, "hooks")).filter((f) => f.endsWith(".js")).sort();

// ----------------------------------------------------------------- harness

let asserts = 0, failures = 0, current = "";
function ok(cond, msg) {
  asserts++;
  if (!cond) { failures++; console.log(`  FAIL [${current}] ${msg}`); }
}
function eq(a, b, msg) {
  const same = JSON.stringify(a) === JSON.stringify(b);
  ok(same, `${msg}: expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`);
}
const tests = [];
const test = (name, fn) => tests.push([name, fn]);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const json = (body, status = 200) => ({ ok: status >= 200 && status < 300, status, json: async () => body });

// Boots a page: html, blimp.js, optional extra hook source, optional real hooks.
async function page(html, { hooks = "", real = false, url = "http://localhost/work?x=1" } = {}) {
  const dom = new JSDOM(
    `<!doctype html><html><head><meta name="csrf-token" content="TOK"></head><body>${html}</body></html>`,
    { runScripts: "outside-only", url, pretendToBeVisual: true }
  );
  const w = dom.window;
  if (!w.CSS) w.CSS = { escape: (s) => String(s).replace(/([^\w-])/g, "\\$1") };
  w.ResizeObserver = class { observe() {} disconnect() {} };
  w.HTMLElement.prototype.scrollIntoView = () => {};
  const calls = [];
  let responder = () => json({});
  w.fetch = (u, o) => { calls.push({ url: u, opts: o || {}, body: o?.body ? JSON.parse(o.body) : undefined }); return Promise.resolve(responder(u, o || {})); };
  w.eval(blimpSrc);
  const registered = [];
  const orig = w.Blimp.hook;
  w.Blimp.hook = (n, d) => { registered.push(n); orig(n, d); };
  if (hooks) w.eval(hooks);
  if (real) for (const f of hookFiles) w.eval(read(`hooks/${f}`));
  await sleep(5); // boot runs in a microtask
  return {
    w, d: w.document, B: w.Blimp, calls, registered,
    respond: (fn) => { responder = fn; },
    $: (s) => w.document.querySelector(s),
  };
}
const patch = (p, regions, extra = {}) => p.B.apply({ regions, ...extra });

const COUNTER = `
Blimp.hook("Counter", {
  mounted() { window.log = window.log || []; this.id = Math.random(); window.log.push("mounted:" + this.el.id); this.handleEvent("ping", (p) => window.log.push("ping:" + p.n)); },
  updated() { window.log.push("updated:" + this.el.id); },
  destroyed() { window.log.push("destroyed:" + this.el.id); },
});`;

// ------------------------------------------------------------------- morph

test("morph keeps an id'd element and its hook instance", async () => {
  const p = await page(`<main id="main"><div id="c" phx-hook=".Counter" class="a">one</div></main>`, { hooks: COUNTER });
  const el = p.$("#c"), inst = p.B.live.get(el);
  ok(inst && inst.id, "hook mounted on load");
  patch(p, { "#main": `<div id="c" phx-hook=".Counter" class="b">two</div>` });
  ok(p.$("#c") === el, "same element node after patch");
  ok(p.B.live.get(p.$("#c")) === inst, "same hook instance after patch");
  eq([el.className, el.textContent], ["b", "two"], "content and class patched");
  eq(p.w.log, ["mounted:c", "updated:c"], "mounted once, updated once");
});

test("morph with identical html fires no updated()", async () => {
  const p = await page(`<main id="main"><div id="c" phx-hook=".Counter">one</div></main>`, { hooks: COUNTER });
  patch(p, { "#main": `<div id="c" phx-hook=".Counter">one</div>` });
  eq(p.w.log, ["mounted:c"], "isEqualNode short-circuit");
});

test("keyed children keep identity when reordered", async () => {
  const p = await page(`<main id="main"><p id="a">A</p><p id="b">B</p><p id="c">C</p></main>`);
  const [a, b, c] = ["#a", "#b", "#c"].map(p.$);
  patch(p, { "#main": `<p id="c">C2</p><p id="a">A</p><p id="b">B</p>` });
  const ids = [...p.d.querySelectorAll("#main > p")].map((n) => n.id);
  eq(ids, ["c", "a", "b"], "order follows the server");
  ok(p.$("#a") === a && p.$("#b") === b && p.$("#c") === c, "all three nodes kept");
  eq(c.textContent, "C2", "moved node patched");
});

test("same-tag unkeyed nodes are patched in place; extras removed", async () => {
  const p = await page(`<main id="main"><ul><li>1</li><li>2</li><li>3</li></ul></main>`);
  const first = p.$("li");
  patch(p, { "#main": `<ul><li>x</li><li>y</li></ul>` });
  ok(p.$("li") === first, "first li kept");
  eq([...p.d.querySelectorAll("li")].map((n) => n.textContent), ["x", "y"], "list shortened");
});

test("phx-update=ignore keeps children and non-data attrs, merges data-*", async () => {
  const p = await page(`<main id="main"><div id="g" phx-hook=".Counter" phx-update="ignore" data-graph="1" class="mine"><svg id="s"></svg></div></main>`, { hooks: COUNTER });
  const g = p.$("#g");
  g.firstChild.setAttribute("data-drawn", "yes");
  patch(p, { "#main": `<div id="g" phx-hook=".Counter" phx-update="ignore" data-graph="2" class="theirs"><i>server</i></div>` });
  ok(p.$("#s") && !p.$("#g i"), "children kept, server children ignored");
  eq(g.className, "mine", "non-data attribute untouched");
  eq(g.dataset.graph, "2", "data-* merged");
  eq(p.w.log, ["mounted:g", "updated:g"], "updated() reported because dataset changed");
  patch(p, { "#main": `<div id="g" phx-hook=".Counter" phx-update="ignore" data-graph="2" class="theirs"><i>x</i></div>` });
  eq(p.w.log, ["mounted:g", "updated:g"], "no updated() when dataset unchanged");
});

test("focused textarea keeps its value and selection", async () => {
  const p = await page(`<main id="main"><form id="f"><textarea id="t" name="t">server</textarea><input id="i" name="i" value="a"></form></main>`);
  const t = p.$("#t");
  t.focus(); t.value = "half typed text"; t.setSelectionRange(3, 7);
  patch(p, { "#main": `<form id="f"><textarea id="t" name="t" class="x">server changed</textarea><input id="i" name="i" value="b"></form>` });
  ok(p.$("#t") === t && p.d.activeElement === t, "same node, still focused");
  eq([t.value, t.selectionStart, t.selectionEnd], ["half typed text", 3, 7], "value and selection kept");
  eq(t.className, "x", "attributes still sync");
  eq(p.$("#i").value, "b", "unfocused input takes the server value");
});

test("checkbox, radio and select values sync from the server", async () => {
  const p = await page(`<main id="main"><form id="f"><input id="c" type="checkbox" name="c"><select id="s" name="s"><option value="1" selected>one</option><option value="2">two</option></select></form></main>`);
  ok(!p.$("#c").checked && p.$("#s").value === "1", "start state");
  patch(p, { "#main": `<form id="f"><input id="c" type="checkbox" name="c" checked><select id="s" name="s"><option value="1">one</option><option value="2" selected>two</option></select></form>` });
  ok(p.$("#c").checked, "checkbox follows server");
  eq(p.$("#s").value, "2", "select follows server");
});

test("a user-changed control survives an unrelated patch", async () => {
  const p = await page(`<main id="main"><input id="i" name="i" value="a"><span id="x">1</span></main>`);
  p.$("#i").value = "typed";
  patch(p, { "#main": `<input id="i" name="i" value="a"><span id="x">2</span>` });
  eq([p.$("#i").value, p.$("#x").textContent], ["typed", "2"], "typed value kept, span patched");
});

// ------------------------------------------------------------------- hooks

test("hook mounted on a node added by a morph; destroyed on removal", async () => {
  const p = await page(`<main id="main"></main>`, { hooks: COUNTER });
  eq(p.w.log, undefined, "nothing mounted yet");
  patch(p, { "#main": `<div id="n1" phx-hook="Counter">new</div>` });
  eq(p.w.log, ["mounted:n1"], "mounted for the added node (name without dot)");
  const el = p.$("#n1");
  patch(p, { "#main": `<span>gone</span>` });
  ok(!el.isConnected && !p.B.live.has(el), "node removed and instance dropped");
  eq(p.w.log, ["mounted:n1", "destroyed:n1"], "destroyed() ran");
});

test("handleEvent dispatches from response events and unregisters on destroyed", async () => {
  const p = await page(`<main id="main"><div id="c" phx-hook=".Counter"></div><button id="b" phx-click="go">go</button></main>`, { hooks: COUNTER });
  p.respond(() => json({ events: [{ name: "ping", payload: { n: 1 } }] }));
  p.$("#b").click();
  await p.B.idle();
  eq(p.w.log, ["mounted:c", "ping:1"], "handler called with payload");
  patch(p, { "#main": `` });
  p.respond(() => json({ events: [{ name: "ping", payload: { n: 2 } }] }));
  await p.B.send("go");
  eq(p.w.log, ["mounted:c", "ping:1", "destroyed:c"], "no dispatch after destroyed()");
});

test("this.pushEvent posts the same way; liveSocket is undefined", async () => {
  const p = await page(`<main id="main"><div id="c" phx-hook=".Push"></div></main>`, {
    hooks: `Blimp.hook("Push", { mounted() { window.ls = this.liveSocket; this.pushEvent("close_chat", {a: "1"}); } });`,
  });
  await p.B.idle();
  eq(p.calls[0].url, "/ev/close_chat", "url");
  eq(p.calls[0].body.payload, { a: "1" }, "payload");
  ok(p.w.ls === undefined, "liveSocket undefined");
});

test("unknown hook throws and shows the error banner", async () => {
  const p = await page(`<main id="main"><div id="x" hidden>x</div></main><div id="server-error" hidden>err</div>`);
  p.respond(() => json({ regions: { "#main": `<div id="q" phx-hook=".Nope"></div>` } }));
  const origErr = p.w.console.error; p.w.console.error = () => {};
  await p.B.send("go");
  p.w.console.error = origErr;
  ok(!p.$("#server-error").hasAttribute("hidden"), "banner shown");
  ok(p.$("#q"), "the page was still patched");
});

// ------------------------------------------------------------------ events

test("click with phx-value-* posts the right request", async () => {
  const p = await page(`<main id="main"><button id="b" phx-click="pick" phx-value-ref="3" phx-value-kind="note">x</button></main>`);
  p.$("#b").click();
  await p.B.idle();
  const c = p.calls[0];
  eq(c.url, "/ev/pick", "url");
  eq(c.opts.method, "POST", "method");
  eq(c.opts.headers["content-type"], "application/json", "content-type");
  eq(c.opts.headers["x-csrf-token"], "TOK", "csrf header");
  eq(c.opts.headers["x-requested-with"], "blimp", "requested-with");
  eq(c.body, { payload: { ref: "3", kind: "note" }, path: "/work?x=1" }, "body");
});

test("click on a child of a phx-click element; loading class comes and goes", async () => {
  const p = await page(`<main id="main"><button id="b" phx-click="e"><span id="s">x</span></button></main>`);
  let release; const gate = new Promise((r) => (release = r));
  p.respond(() => gate.then(() => json({})));
  p.$("#s").click();
  await sleep(2);
  ok(p.$("#b").classList.contains("phx-click-loading"), "loading class while in flight");
  ok(p.d.documentElement.classList.contains("blimp-busy"), "html busy class");
  release(); await p.B.idle();
  ok(!p.$("#b").classList.contains("phx-click-loading"), "loading class removed");
  ok(!p.d.documentElement.classList.contains("blimp-busy"), "busy class removed");
});

test("submit sends all fields (last wins), disable-with swaps and restores", async () => {
  const p = await page(`<main id="main"><form id="f" phx-submit="save"><input name="a" value="1"><input name="a" value="2"><textarea name="t">hi</textarea><button id="btn" phx-disable-with="Saving...">Save</button></form></main>`);
  let release; const gate = new Promise((r) => (release = r));
  p.respond(() => gate.then(() => json({})));
  p.$("#btn").click();
  await sleep(2);
  eq(p.calls[0].url, "/ev/save", "url");
  eq(p.calls[0].body.payload, { a: "2", t: "hi" }, "payload");
  eq([p.$("#btn").textContent, p.$("#btn").disabled], ["Saving...", true], "button swapped and disabled");
  ok(p.$("#f").classList.contains("phx-submit-loading"), "submit loading class");
  release(); await p.B.idle();
  eq([p.$("#btn").textContent, p.$("#btn").disabled], ["Save", false], "button restored");
});

test("change sends fields plus _target, debounced", async () => {
  const p = await page(`<main id="main"><form id="f" phx-change="search"><input id="q" name="q" phx-debounce="30" value=""><input type="checkbox" id="k" name="k" value="y"></form></main>`);
  const q = p.$("#q");
  for (const v of ["a", "ab", "abc"]) { q.value = v; q.dispatchEvent(new p.w.Event("input", { bubbles: true })); }
  eq(p.calls.length, 0, "nothing sent before the debounce");
  await sleep(60); await p.B.idle();
  eq(p.calls.length, 1, "one request after the debounce");
  eq(p.calls[0].body.payload, { q: "abc", _target: ["q"] }, "payload with _target");
  p.$("#k").click();
  await p.B.idle();
  eq(p.calls[1].body.payload, { q: "abc", k: "y", _target: ["k"] }, "checkbox sends on change");
});

test("events are serialised in order", async () => {
  const p = await page(`<main id="main"></main>`);
  const gates = [];
  p.respond((u) => new Promise((r) => gates.push(() => r(json({})))));
  const a = p.B.send("first"), b = p.B.send("second");
  await sleep(5);
  eq(p.calls.map((c) => c.url), ["/ev/first"], "second waits for the first");
  gates[0](); await sleep(5);
  eq(p.calls.map((c) => c.url), ["/ev/first", "/ev/second"], "second goes after the first answers");
  gates[1](); await Promise.all([a, b]);
});

test("non-2xx shows #server-error and re-enables the control", async () => {
  const p = await page(`<main id="main"><button id="b" phx-click="boom" phx-disable-with="...">Go</button></main><div id="server-error" hidden>err</div>`);
  p.respond(() => json({}, 500));
  const origErr = p.w.console.error; p.w.console.error = () => {};
  p.$("#b").click();
  await p.B.idle();
  p.w.console.error = origErr;
  ok(!p.$("#server-error").hasAttribute("hidden"), "banner visible");
  eq([p.$("#b").disabled, p.$("#b").textContent], [false, "Go"], "control re-enabled");
  p.respond(() => json({}));
  p.$("#b").click(); await p.B.idle();
  ok(p.$("#server-error").hasAttribute("hidden"), "banner hidden again after a good reply");
});

test("redirect, title and flash in a response", async () => {
  const p = await page(`<main id="main"></main><div id="flash-group"></div>`);
  patch(p, {}, { title: "New title", flash: { info: "Saved." } });
  eq(p.d.title, "New title", "title");
  eq(p.$("#flash-info p").textContent, "Saved.", "flash rendered");
  patch(p, {}, { redirect: "#done" });
  eq(p.w.location.hash, "#done", "redirect navigates");
});

test("theme click dispatches phx:set-theme with the element as target", async () => {
  const p = await page(`<main id="main"><button id="t" data-phx-theme="dark">dark</button></main>`);
  let seen;
  p.w.addEventListener("phx:set-theme", (e) => (seen = e.target.dataset.phxTheme));
  p.$("#t").click();
  eq(seen, "dark", "inline-script contract");
  eq(p.calls.length, 0, "no server request");
});

test("phx-click-away fires only for clicks outside", async () => {
  const p = await page(`<main id="main"><div id="panel" phx-click-away="toggle_linking"><button id="in">in</button></div><p id="out">out</p></main>`);
  p.$("#in").click(); await p.B.idle();
  eq(p.calls.length, 0, "inside click ignored");
  p.$("#out").click(); await p.B.idle();
  eq(p.calls.map((c) => c.url), ["/ev/toggle_linking"], "outside click fires the event");
});

test("phx-window-keydown honours phx-key", async () => {
  const p = await page(`<main id="main"><div phx-window-keydown="rename_cancel" phx-key="Escape"></div></main>`);
  p.w.dispatchEvent(new p.w.KeyboardEvent("keydown", { key: "a" })); await p.B.idle();
  eq(p.calls.length, 0, "other keys ignored");
  p.w.dispatchEvent(new p.w.KeyboardEvent("keydown", { key: "Escape" })); await p.B.idle();
  eq(p.calls[0].body.payload, { key: "Escape" }, "Escape sends {key}");
});

// ----------------------------------------------------------------- polling

test("poll starts with data-poll, sends the right GET, stops when it goes", async () => {
  const p = await page(`<main id="main"><i id="w" data-poll="0.1">waiting</i></main>`);
  let n = 0;
  p.respond(() => json(++n < 3 ? { regions: { "#main": `<i id="w" data-poll="0.1">waiting ${n}</i>` } } : { regions: { "#main": `<b>done</b>` } }));
  await sleep(450);
  const gets = p.calls.filter((c) => !c.opts.method);
  eq(gets.length, 3, "polled until the attribute disappeared, then stopped");
  eq([gets[0].url, gets[0].opts.headers["x-requested-with"], gets[0].opts.headers.accept], ["/work?x=1", "blimp", "application/json"], "GET headers");
  await sleep(250);
  eq(p.calls.filter((c) => !c.opts.method).length, 3, "no more polls after stop");
});

test("no polling without data-poll; an event reply re-polls immediately", async () => {
  const p = await page(`<main id="main"><button id="b" phx-click="go">go</button></main>`);
  await sleep(150);
  eq(p.calls.length, 0, "idle page does not poll");
  p.respond((u, o) => (o.method === "POST" ? json({ regions: { "#main": `<i data-poll="30">w</i>` } }) : json({})));
  p.$("#b").click();
  await sleep(30); await p.B.idle();
  eq(p.calls.map((c) => (c.opts.method || "GET") + " " + c.url), ["POST /ev/go", "GET /work?x=1"], "immediate re-poll after the event");
});

test("poll pauses while typing in a non-empty textarea", async () => {
  const p = await page(`<main id="main"><i data-poll="0.1">w</i><textarea id="t"></textarea></main>`);
  const t = p.$("#t"); t.focus(); t.value = "typing";
  await sleep(350);
  eq(p.calls.length, 0, "paused while typing");
  t.value = ""; t.blur();
  await sleep(250);
  ok(p.calls.length >= 1, "resumes after blur");
  p.respond(() => json({ regions: { "#main": `<b>x</b>` } }));
});

test("poll pauses while a selection is open in .mg-read-body", async () => {
  const p = await page(`<main id="main"><i data-poll="0.1">w</i><div class="mg-read-body"><p id="para">some words to select</p></div></main>`);
  const r = p.d.createRange(); r.selectNodeContents(p.$("#para").firstChild);
  p.w.getSelection().removeAllRanges(); p.w.getSelection().addRange(r);
  await sleep(350);
  eq(p.calls.length, 0, "paused during selection");
  p.w.getSelection().removeAllRanges();
  await sleep(250);
  ok(p.calls.length >= 1, "resumes when the selection collapses");
  p.respond(() => json({ regions: { "#main": `<b>x</b>` } }));
});

// ------------------------------------------------------- ported real hooks

test("all 23 hooks register under the contracted names", async () => {
  const p = await page(`<main id="main"></main>`, { real: true });
  const want = "LinkChat LinkChatComposer StickDown Walk Clock LaneTree Hover Minimap Steer Deck Editor Selection Share SummaryVault MarginNotes StickToBottom ChatComposer Wiring Reveal Tree Weave Follow Rotate".split(" ");
  eq([...p.registered].sort(), want.sort(), "hook names");
});

test("Steer: ignored textarea keeps half-typed text, updated() re-measures", async () => {
  const p = await page(`<main id="main"><form id="sf"><textarea id="rw-steer" name="s" phx-hook=".Steer" phx-update="ignore" data-n="1"></textarea></form></main>`, { real: true });
  const ta = p.$("#rw-steer"); ta.value = "make it shorter, and warmer";
  let grew = 0; const inst = p.B.live.get(ta); const g = inst.grow; inst.grow = () => { grew++; g(); };
  patch(p, { "#main": `<form id="sf"><textarea id="rw-steer" name="s" phx-hook=".Steer" phx-update="ignore" data-n="2">server text</textarea></form>` });
  eq([ta.value, p.$("#rw-steer") === ta], ["make it shorter, and warmer", true], "text and node kept");
  eq(grew, 1, "updated() ran because data-n changed");
});

test("Rotate: ignored span keeps the hook's text and class", async () => {
  const p = await page(`<main id="main"><span id="mut" class="mg-mutter" phx-hook=".Rotate" phx-update="ignore" data-lines='["a","b"]'>a</span></main>`, { real: true });
  const s = p.$("#mut"); s.textContent = "b"; s.classList.add("out");
  patch(p, { "#main": `<span id="mut" class="mg-mutter" phx-hook=".Rotate" phx-update="ignore" data-lines='["a","b"]'>a</span><i>more</i>` });
  eq([s.textContent, s.className, p.$("#mut") === s], ["b", "mg-mutter out", true], "ignore rule holds");
  patch(p, { "#main": `` });
  ok(!p.B.live.has(s), "destroyed (timers cleared) when the dots go");
});

test("MarginNotes: delegated listeners work on notes added after mount", async () => {
  const grid = (extra) => `<div id="grid" class="collapsed" phx-hook=".MarginNotes"><div class="mg-read-rail">${extra.slot}</div><div class="mg-read-body"><p>${extra.mark}</p></div></div>`;
  const first = { slot: `<div class="mg-note-slot" data-anchor="a">A</div>`, mark: `<mark id="anchor-a">a</mark>` };
  const both = { slot: first.slot + `<div class="mg-note-slot" data-anchor="b">B</div>`, mark: first.mark + `<mark id="anchor-b">b</mark>` };
  const p = await page(`<main id="main">${grid(first)}</main>`, { real: true });
  patch(p, { "#main": grid(both) });
  const mb = p.$('mark#anchor-b'), sb = p.$('.mg-note-slot[data-anchor="b"]');
  // jsdom has no layout: give the mark a position or reposition() sees it scrolled away
  mb.getBoundingClientRect = () => ({ top: 100, bottom: 120, left: 50, right: 90, width: 40, height: 20 });
  mb.dispatchEvent(new p.w.MouseEvent("mouseover", { bubbles: true }));
  ok(sb.classList.contains("peek"), "hover on a mark added by a morph peeks its note");
  mb.dispatchEvent(new p.w.MouseEvent("mouseout", { bubbles: true }));
  ok(!sb.classList.contains("peek"), "mouseout puts it away");
  mb.dispatchEvent(new p.w.MouseEvent("click", { bubbles: true }));
  ok(mb.classList.contains("pinned") && sb.classList.contains("peek"), "click pins");
  sb.dispatchEvent(new p.w.MouseEvent("mouseover", { bubbles: true }));
  ok(mb.classList.contains("lit"), "hovering a note lights its highlight");
});

test("ChatComposer: chat:clear event empties the textarea", async () => {
  const p = await page(`<main id="main"><form id="chat-form" phx-hook=".ChatComposer" phx-submit="chat_send"><textarea name="q"></textarea></form></main>`, { real: true });
  const ta = p.$("textarea"); ta.value = "hello";
  p.respond(() => json({ events: [{ name: "chat:clear", payload: {} }] }));
  ta.dispatchEvent(new p.w.KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }));
  await p.B.idle();
  eq(p.calls[0].url, "/ev/chat_send", "Enter submitted the form through the delegated listener");
  eq(ta.value, "", "cleared by handleEvent");
});

test("app.js bundle boots, topbar loads, real hooks mount on load", async () => {
  const bundle = path.join(js, "app.js");
  if (!fs.existsSync(bundle)) { ok(false, "static/js/app.js missing: run static/js/bundle.sh"); return; }
  const dom = new JSDOM(`<!doctype html><body><main id="main"><span id="read-clock" phx-hook=".Clock" data-since="0">x</span><button id="b" phx-click="e">e</button></main></body>`,
    { runScripts: "outside-only", url: "http://localhost/", pretendToBeVisual: true });
  const w = dom.window;
  w.fetch = () => Promise.resolve(json({}));
  w.eval(fs.readFileSync(bundle, "utf8"));
  await sleep(5);
  ok(typeof w.topbar?.show === "function", "topbar global present");
  ok(w.Blimp.live.has(w.document.getElementById("read-clock")), "Clock mounted from the bundle");
  w.document.getElementById("b").click();
  await w.Blimp.idle();
  ok(true, "click with topbar present does not throw");
});

// -------------------------------------------------------------------- main

for (const [name, fn] of tests) {
  current = name;
  const before = failures;
  try { await fn(); } catch (e) { failures++; asserts++; console.log(`  ERROR [${name}] ${e.stack || e}`); }
  console.log(`${failures === before ? "ok  " : "FAIL"} ${name}`);
}
console.log(`\n${asserts} assertions, ${failures} failed, ${tests.length} tests`);
process.exit(failures ? 1 : 0);
