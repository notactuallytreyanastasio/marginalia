// blimp.js: the browser half of Marginalia on Blimp.
//
// The server renders HTML. Every user event is `POST /ev/<name>`; the answer
// is JSON naming regions of the page (CSS selector -> new innerHTML), events
// for hooks, and optionally a redirect, a title and flash messages. Regions
// are morphed in, not replaced, so elements with an id keep their identity,
// and so do the hook instances living on them.
//
// The templates keep Phoenix's attribute names (phx-click, phx-value-*,
// phx-submit, phx-change, phx-debounce, phx-click-away, phx-window-keydown,
// phx-key, phx-hook, phx-update="ignore", phx-disable-with, phx-mounted,
// data-phx-theme); this file reads them. There is no socket: server pushes
// are a poll of the current URL while any [data-poll] element exists.
(() => {
  "use strict";

  const hooks = {};                 // name -> definition
  const live = new Map();           // element -> hook instance
  const handlers = new Map();       // event name -> Set<{fn, owner}>
  const mountedOnce = new WeakSet(); // elements whose phx-mounted already ran
  const touched = new Set();        // elements a morph changed

  let queue = Promise.resolve();
  let busy = 0;

  const $ = (sel, root = document) => root.querySelector(sel);
  const csrf = () => $("meta[name='csrf-token']")?.getAttribute("content") || "";
  const here = () => location.pathname + location.search;
  const fail = (e) => { try { console.error(e); } catch (_) {} };

  // ---------------------------------------------------------------- busy UI

  function busyStart() {
    if (++busy === 1) {
      document.documentElement.classList.add("blimp-busy");
      try { window.topbar?.show(300); } catch (_) {}
    }
  }
  function busyStop() {
    if (--busy === 0) {
      document.documentElement.classList.remove("blimp-busy");
      try { window.topbar?.hide(); } catch (_) {}
    }
  }

  // ------------------------------------------------------------ banners, flash

  function banner(id, on) {
    const el = document.getElementById(id);
    if (el) el.toggleAttribute("hidden", !on);
    return !!el;
  }

  function showFlash(flash) {
    for (const [kind, msg] of Object.entries(flash || {})) {
      if (!msg) continue;
      let el = document.getElementById(`flash-${kind}`);
      if (!el) {
        el = document.createElement("div");
        el.id = `flash-${kind}`;
        el.setAttribute("role", "alert");
        el.className = "toast toast-top toast-end z-50";
        el.innerHTML = `<div class="alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap alert-${kind}"><div><p></p></div></div>`;
        ($("#flash-group") || document.body).appendChild(el);
      }
      const p = [...el.querySelectorAll("p")].pop();
      if (p) p.textContent = msg; else el.textContent = msg;
      el.removeAttribute("hidden");
    }
  }

  // ------------------------------------------------------------- transport

  // Run `job` after everything queued before it. A job never rejects.
  function enqueue(job) {
    queue = queue.then(job, job);
    return queue;
  }

  // POST /ev/<name>. `from` is the element to mark as loading; `done` is
  // called when the request settles (to restore disable-with text).
  function send(name, payload = {}, from, loadingClass = "phx-click-loading", done) {
    from?.classList.add(loadingClass);
    busyStart();
    return enqueue(async () => {
      try {
        const res = await fetch(`/ev/${name}`, {
          method: "POST",
          credentials: "same-origin",
          headers: {
            "content-type": "application/json",
            "x-csrf-token": csrf(),
            "x-requested-with": "blimp",
          },
          body: JSON.stringify({ payload, path: here() }),
        });
        if (!res.ok) throw new Error(`POST /ev/${name}: ${res.status}`);
        const data = await res.json();
        banner("server-error", false);
        banner("client-error", false);
        apply(data);
        if ($("[data-poll]")) pollNow();
      } catch (e) {
        fail(e);
        // fetch itself failing is a TypeError: the network, not the server
        if (!(e instanceof TypeError && banner("client-error", true))) banner("server-error", true);
      } finally {
        from?.classList.remove(loadingClass);
        done?.();
        busyStop();
      }
    });
  }

  // --------------------------------------------------------- applying a reply

  function apply(data) {
    const { regions = {}, events = [], redirect, title, flash } = data || {};
    if (redirect) { location.href = redirect; return; }
    if (title) document.title = title;
    if (flash) showFlash(flash);

    const errors = [];
    const focus = document.activeElement;
    const sel = focus && "selectionStart" in focus ? [focus.selectionStart, focus.selectionEnd] : null;

    for (const [selector, html] of Object.entries(regions)) {
      const el = $(selector);
      if (!el) { errors.push(new Error(`region ${selector} is not on the page`)); continue; }
      const to = el.cloneNode(false);
      to.innerHTML = html;
      if (!el.isEqualNode(to)) {
        morphChildren(el, to);
        touched.add(el);
      }
    }

    // a node that was moved or replaced can drop focus: give it back
    if (focus && focus !== document.body && focus.isConnected && document.activeElement !== focus) {
      focus.focus({ preventScroll: true });
      if (sel && sel[0] != null) { try { focus.setSelectionRange(sel[0], sel[1]); } catch (_) {} }
    }

    lifecycle(errors);

    for (const ev of events) {
      for (const h of [...(handlers.get(ev.name) || [])]) {
        try { h.fn(ev.payload || {}); } catch (e) { errors.push(e); }
      }
    }
    if (errors.length) { errors.slice(1).forEach(fail); throw errors[0]; }
  }

  // ------------------------------------------------------------------ morph

  const kindOf = (n) => (n.nodeType === 1 ? n.nodeName : n.nodeType);

  function morphChildren(from, to) {
    const keyed = new Map();
    for (const n of from.children) if (n.id) keyed.set(n.id, n);
    const wanted = new Set();
    for (const n of to.children) if (n.id) wanted.add(n.id);

    const kept = new Set();
    let cur = from.firstChild;

    for (const want of [...to.childNodes]) {
      let have = null;
      if (want.nodeType === 1 && want.id) {
        have = keyed.get(want.id) || null;
        if (have && kept.has(have)) have = null;       // duplicate id: treat as new
      } else {
        // step over nodes reserved for a later keyed child
        while (cur && cur.nodeType === 1 && cur.id && wanted.has(cur.id)) cur = cur.nextSibling;
        if (cur && !(cur.nodeType === 1 && cur.id) && kindOf(cur) === kindOf(want)) have = cur;
      }

      if (have) {
        if (have === cur) cur = cur.nextSibling;
        else if (have.nextSibling !== cur) from.insertBefore(have, cur);
        morphNode(have, want);
        kept.add(have);
      } else {
        from.insertBefore(want, cur);
        kept.add(want);
      }
    }

    for (const n of [...from.childNodes]) if (!kept.has(n)) n.remove();
  }

  const isIgnored = (el) => el.getAttribute("phx-update") === "ignore";
  const dataOf = (el) => JSON.stringify(Object.entries(el.dataset).sort());

  function morphNode(a, b) {
    if (a.nodeType !== 1) {
      if (a.nodeValue !== b.nodeValue) a.nodeValue = b.nodeValue;
      return;
    }
    if (a.isEqualNode(b)) return;

    // phx-update="ignore": the server does not own the children or the
    // non-data attributes. It still owns data-*, and a changed dataset is
    // reported so the hook can redraw (LaneTree, Weave read data-graph).
    if (isIgnored(a)) {
      const before = dataOf(a);
      for (const { name, value } of b.attributes) {
        if (name.startsWith("data-") && a.getAttribute(name) !== value) a.setAttribute(name, value);
      }
      if (dataOf(a) !== before) touched.add(a);
      return;
    }

    const tag = a.tagName;
    const focused = a === document.activeElement;

    // what the server changed, decided before attributes are synced
    const valueChanged = a.getAttribute("value") !== b.getAttribute("value");
    const checkedChanged = a.hasAttribute("checked") !== b.hasAttribute("checked");

    for (const { name, value } of b.attributes) {
      if (a.getAttribute(name) !== value) a.setAttribute(name, value);
    }
    for (const { name } of [...a.attributes]) {
      if (!b.hasAttribute(name)) a.removeAttribute(name);
    }

    if (tag === "INPUT") {
      if ((a.type === "checkbox" || a.type === "radio")) {
        if (checkedChanged && !focused) a.checked = b.checked;
      } else if (a.type !== "file" && valueChanged && !focused) {
        a.value = b.getAttribute("value") ?? "";
      }
    } else if (tag === "TEXTAREA") {
      // children are the default value; the live value is the user's
      const changed = a.defaultValue !== b.defaultValue;
      if (changed) a.defaultValue = b.defaultValue;
      if (changed && !focused) a.value = b.defaultValue;
    } else if (tag === "SELECT") {
      const val = b.value;
      morphChildren(a, b);
      if (!focused && !a.multiple && a.value !== val) a.value = val;
    } else {
      morphChildren(a, b);
    }
    touched.add(a);
  }

  // -------------------------------------------------------------- lifecycle

  const hookName = (el) => (el.getAttribute("phx-hook") || "").trim().replace(/^\./, "");

  function mountHook(el) {
    const name = hookName(el);
    const def = hooks[name];
    if (!def) throw new Error(`unknown hook "${name}" on <${el.localName}${el.id ? " id=" + el.id : ""}>`);
    const h = Object.create(def);
    h.el = el;
    h.liveSocket = undefined;
    h.pushEvent = (n, p = {}) => send(n, p, el);
    h.handleEvent = (n, fn) => {
      if (!handlers.has(n)) handlers.set(n, new Set());
      handlers.get(n).add({ fn, owner: h });
    };
    live.set(el, h);
    h.mounted?.();
  }

  function unmountHook(el, h) {
    live.delete(el);
    for (const set of handlers.values()) for (const r of [...set]) if (r.owner === h) set.delete(r);
    h.destroyed?.();
  }

  // After a morph (or on load): destroyed for hooks whose element left the
  // page, updated for those the morph touched, mounted for new ones, and
  // phx-mounted once for each new element carrying it. Every callback runs
  // even if one throws; the first error is rethrown by the caller.
  function lifecycle(errors = []) {
    const run = (f) => { try { f(); } catch (e) { errors.push(e); } };

    for (const [el, h] of [...live]) if (!el.isConnected) run(() => unmountHook(el, h));

    const changed = [...touched];
    touched.clear();
    for (const el of changed) {
      const h = live.get(el);
      if (h && el.isConnected) run(() => h.updated?.());
    }

    for (const el of document.querySelectorAll("[phx-hook]")) {
      if (!live.has(el)) run(() => mountHook(el));
    }

    for (const el of document.querySelectorAll("[phx-mounted]")) {
      if (mountedOnce.has(el)) continue;
      mountedOnce.add(el);
      el.removeAttribute("hidden");
      if (el.matches("input,textarea,select,button,a[href],[tabindex],[contenteditable]")) {
        run(() => el.focus());
      }
    }
    return errors;
  }

  // ----------------------------------------------------------------- events

  const valuesOf = (el) => {
    const out = {};
    for (const a of el.attributes) if (a.name.startsWith("phx-value-")) out[a.name.slice(10)] = a.value;
    return out;
  };

  function formObject(form, submitter) {
    let fd;
    try { fd = submitter ? new FormData(form, submitter) : new FormData(form); }
    catch (_) { fd = new FormData(form); }
    const out = {};
    for (const [k, v] of fd.entries()) out[k] = typeof v === "string" ? v : v.name;
    return out;
  }

  // phx-disable-with: swap the label and disable until the request settles.
  function disableWith(scope) {
    const els = scope.matches?.("[phx-disable-with]") ? [scope] : [...scope.querySelectorAll("[phx-disable-with]")];
    const undo = els.map((el) => {
      const isInput = el.tagName === "INPUT";
      const prev = isInput ? el.value : el.textContent;
      const next = el.getAttribute("phx-disable-with");
      const wasDisabled = el.disabled;
      if (isInput) el.value = next; else el.textContent = next;
      el.disabled = true;
      return () => {
        const now = isInput ? el.value : el.textContent;
        if (now === next) { if (isInput) el.value = prev; else el.textContent = prev; }
        if (!wasDisabled) el.disabled = false;
      };
    });
    return () => undo.forEach((f) => f());
  }

  document.addEventListener("click", (e) => {
    const t = e.target;
    if (!(t instanceof Element)) return;

    const theme = t.closest("[data-phx-theme]");
    if (theme) {
      theme.dispatchEvent(new CustomEvent("phx:set-theme", { bubbles: true }));
    }

    // dismiss a toast the server rendered
    const toast = t.closest("#flash-group [role=alert]");
    if (toast && !toast.hasAttribute("phx-click")) toast.setAttribute("hidden", "");

    // outside clicks
    if (t.isConnected) {
      for (const el of document.querySelectorAll("[phx-click-away]")) {
        if (!el.contains(t)) send(el.getAttribute("phx-click-away"), valuesOf(el), el);
      }
    }

    const el = t.closest("[phx-click]");
    if (!el || el.disabled) return;
    if (el.tagName === "A" && el.getAttribute("href") === "#") e.preventDefault();
    const undo = el.hasAttribute("phx-disable-with") ? disableWith(el) : undefined;
    send(el.getAttribute("phx-click"), valuesOf(el), el, "phx-click-loading", undo);
  });

  document.addEventListener("submit", (e) => {
    const form = e.target;
    if (!(form instanceof HTMLFormElement) || !form.hasAttribute("phx-submit")) return;
    e.preventDefault();
    flushChange(form);
    const payload = formObject(form, e.submitter);
    const undo = disableWith(form);
    send(form.getAttribute("phx-submit"), payload, form, "phx-submit-loading", undo);
  });

  // phx-change. Text-like controls report on `input` (debounced by
  // phx-debounce on the control or its form); checkboxes, radios, selects,
  // files and ranges report on `change`. phx-debounce="blur" waits for blur.
  const timers = new WeakMap();   // form -> {t, run}
  const NOW = /^(checkbox|radio|file|range|color|date|time|datetime-local|month|week)$/;

  const isChoice = (t) => t.tagName === "SELECT" || (t.tagName === "INPUT" && NOW.test(t.type));

  function sendChange(form, target) {
    const payload = formObject(form);
    payload._target = [target.name || ""];
    send(form.getAttribute("phx-change"), payload, form, "phx-change-loading");
  }

  function flushChange(form) {
    const p = timers.get(form);
    if (!p) return;
    clearTimeout(p.t);
    timers.delete(form);
    p.run();
  }

  function onChange(e, kind) {
    const t = e.target;
    if (!(t instanceof Element) || !t.name) return;
    const form = t.closest("form[phx-change]");
    if (!form) return;
    const choice = isChoice(t);
    if (kind === "input" && choice) return;
    if (kind === "change" && !choice) return;
    const wait = t.getAttribute("phx-debounce") ?? form.getAttribute("phx-debounce");
    if (wait === "blur") return;   // handled on focusout
    const ms = parseInt(wait, 10) || 0;
    const run = () => sendChange(form, t);
    const prev = timers.get(form);
    if (prev) clearTimeout(prev.t);
    if (!ms) { timers.delete(form); run(); return; }
    timers.set(form, { run, t: setTimeout(() => { timers.delete(form); run(); }, ms) });
  }
  document.addEventListener("input", (e) => onChange(e, "input"));
  document.addEventListener("change", (e) => onChange(e, "change"));
  document.addEventListener("focusout", (e) => {
    const t = e.target;
    if (!(t instanceof Element) || !t.name) return;
    const form = t.closest("form[phx-change]");
    if (form && (t.getAttribute("phx-debounce") ?? form.getAttribute("phx-debounce")) === "blur") sendChange(form, t);
    pollKick();
  });

  window.addEventListener("keydown", (e) => {
    for (const el of document.querySelectorAll("[phx-window-keydown]")) {
      const key = el.getAttribute("phx-key");
      if (key && key !== e.key) continue;
      send(el.getAttribute("phx-window-keydown"), { key: e.key }, el);
    }
  });

  // ---------------------------------------------------------------- polling

  let pollTimer = null;
  let pollQueued = false;
  let pollWaiting = false;   // the last tick was skipped; poll as soon as allowed

  function pollPaused() {
    const s = document.getSelection?.();
    if (s && !s.isCollapsed && s.anchorNode) {
      const n = s.anchorNode.nodeType === 1 ? s.anchorNode : s.anchorNode.parentElement;
      if (n?.closest?.(".mg-read-body")) return true;
    }
    const a = document.activeElement;
    return !!(a && a.tagName === "TEXTAREA" && a.value !== "");
  }

  function pollSchedule() {
    clearTimeout(pollTimer);
    pollTimer = null;
    const el = $("[data-poll]");
    if (!el) return;
    const secs = parseFloat(el.getAttribute("data-poll"));
    pollTimer = setTimeout(pollNow, Math.max(0.1, secs > 0 ? secs : 2) * 1000);
  }

  function pollNow() {
    if (pollQueued) return;
    if (!$("[data-poll]")) { pollWaiting = false; return pollSchedule(); }
    if (pollPaused()) { pollWaiting = true; return pollSchedule(); }
    pollQueued = true;
    clearTimeout(pollTimer);
    enqueue(async () => {
      try {
        const res = await fetch(here(), {
          credentials: "same-origin",
          headers: { "x-requested-with": "blimp", accept: "application/json" },
        });
        if (!res.ok) throw new Error(`poll ${res.status}`);
        const data = await res.json();
        if (pollPaused()) { pollWaiting = true; return; }   // began typing/selecting meanwhile
        pollWaiting = false;
        banner("server-error", false);
        apply(data);
      } catch (e) {
        fail(e);
        banner("server-error", true);
      } finally {
        pollQueued = false;
        pollSchedule();
      }
    });
  }

  function pollKick() { if (pollWaiting) pollNow(); }
  document.addEventListener("selectionchange", pollKick);

  // ------------------------------------------------------------------- boot

  function boot() {
    try {
      window.topbar?.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
    } catch (_) {}
    const errors = lifecycle();
    pollSchedule();
    if (errors.length) { errors.slice(1).forEach(fail); throw errors[0]; }
  }

  window.Blimp = {
    hook: (name, def) => { hooks[name] = def; },
    send,
    apply,
    morph: (from, to) => { morphChildren(from, to); touched.add(from); lifecycle(); },
    mount: lifecycle,
    poll: pollSchedule,
    idle: () => queue,
    live,
  };

  // hooks register after this file runs (same bundle), so boot after the script
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
  else queueMicrotask(boot);
})();
