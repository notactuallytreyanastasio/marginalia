/* ---- vendor/topbar.js ---- */
/**
 * @license MIT
 * topbar 3.0.0
 * http://buunguyen.github.io/topbar
 * Copyright (c) 2024 Buu Nguyen
 */
(function (window, document) {
  "use strict";

  var canvas,
    currentProgress,
    showing,
    progressTimerId = null,
    fadeTimerId = null,
    delayTimerId = null,
    addEvent = function (elem, type, handler) {
      if (elem.addEventListener) elem.addEventListener(type, handler, false);
      else if (elem.attachEvent) elem.attachEvent("on" + type, handler);
      else elem["on" + type] = handler;
    },
    options = {
      autoRun: true,
      barThickness: 3,
      barColors: {
        0: "rgba(26,  188, 156, .9)",
        ".25": "rgba(52,  152, 219, .9)",
        ".50": "rgba(241, 196, 15,  .9)",
        ".75": "rgba(230, 126, 34,  .9)",
        "1.0": "rgba(211, 84,  0,   .9)",
      },
      shadowBlur: 10,
      shadowColor: "rgba(0,   0,   0,   .6)",
      className: null,
    },
    repaint = function () {
      canvas.width = window.innerWidth;
      canvas.height = options.barThickness * 5; // need space for shadow

      var ctx = canvas.getContext("2d");
      ctx.shadowBlur = options.shadowBlur;
      ctx.shadowColor = options.shadowColor;

      var lineGradient = ctx.createLinearGradient(0, 0, canvas.width, 0);
      for (var stop in options.barColors)
        lineGradient.addColorStop(stop, options.barColors[stop]);
      ctx.lineWidth = options.barThickness;
      ctx.beginPath();
      ctx.moveTo(0, options.barThickness / 2);
      ctx.lineTo(
        Math.ceil(currentProgress * canvas.width),
        options.barThickness / 2
      );
      ctx.strokeStyle = lineGradient;
      ctx.stroke();
    },
    createCanvas = function () {
      canvas = document.createElement("canvas");
      var style = canvas.style;
      style.position = "fixed";
      style.top = style.left = style.right = style.margin = style.padding = 0;
      style.zIndex = 100001;
      style.display = "none";
      if (options.className) canvas.classList.add(options.className);
      addEvent(window, "resize", repaint);
    },
    topbar = {
      config: function (opts) {
        for (var key in opts)
          if (options.hasOwnProperty(key)) options[key] = opts[key];
      },
      show: function (delay) {
        if (showing) return;
        if (delay) {
          if (delayTimerId) return;
          delayTimerId = setTimeout(() => topbar.show(), delay);
        } else {
          showing = true;
          if (fadeTimerId !== null) window.cancelAnimationFrame(fadeTimerId);
          if (!canvas) createCanvas();
          if (!canvas.parentElement) document.body.appendChild(canvas);
          canvas.style.opacity = 1;
          canvas.style.display = "block";
          topbar.progress(0);
          if (options.autoRun) {
            (function loop() {
              progressTimerId = window.requestAnimationFrame(loop);
              topbar.progress(
                "+" + 0.05 * Math.pow(1 - Math.sqrt(currentProgress), 2)
              );
            })();
          }
        }
      },
      progress: function (to) {
        if (typeof to === "undefined") return currentProgress;
        if (typeof to === "string") {
          to =
            (to.indexOf("+") >= 0 || to.indexOf("-") >= 0
              ? currentProgress
              : 0) + parseFloat(to);
        }
        currentProgress = to > 1 ? 1 : to;
        repaint();
        return currentProgress;
      },
      hide: function () {
        clearTimeout(delayTimerId);
        delayTimerId = null;
        if (!showing) return;
        showing = false;
        if (progressTimerId != null) {
          window.cancelAnimationFrame(progressTimerId);
          progressTimerId = null;
        }
        (function loop() {
          if (topbar.progress("+.1") >= 1) {
            canvas.style.opacity -= 0.05;
            if (canvas.style.opacity <= 0.05) {
              canvas.style.display = "none";
              fadeTimerId = null;
              return;
            }
          }
          fadeTimerId = window.requestAnimationFrame(loop);
        })();
      },
    };

  if (typeof module === "object" && typeof module.exports === "object") {
    module.exports = topbar;
  } else if (typeof define === "function" && define.amd) {
    define(function () {
      return topbar;
    });
  } else {
    this.topbar = topbar;
  }
}.call(this, window, document));

/* ---- blimp.js ---- */
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
    // data-confirm, as phoenix_html did: a cancelled confirm sends nothing.
    if (el.dataset.confirm && !window.confirm(el.dataset.confirm)) return;
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

/* ---- hooks/ChatComposer.js ---- */
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

/* ---- hooks/Clock.js ---- */
(() => {
// Counts up from when the read started. Server-side ticking would mean
// a message a second per viewer to render a number nobody acts on.
Blimp.hook("Clock", {
  mounted() { this.tick(); this.t = setInterval(() => this.tick(), 1000); },
  destroyed() { clearInterval(this.t); },
  tick() {
    const since = Number(this.el.dataset.since);
    if (!since) return;
    const s = Math.max(0, Math.floor(Date.now() / 1000) - since);
    this.el.textContent = Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
  },
});
})();

/* ---- hooks/Deck.js ---- */
(() => {
// One slot holding several notes of the same kind, one visible.
//
// Every card is in the DOM; this only moves the `on` class. No
// round trip to read the next note, and nothing to re-fetch when
// you flip back. The cards share a single grid cell, so the slot
// is as tall as the tallest of them and flipping never changes
// the height — which matters here more than it looks, because
// the rail is measured and a slot that grew would push every
// note below it off its own line.
Blimp.hook("Deck", {
  mounted() {
    this.at = 0;
    this.onClick = (e) => {
      const step = e.target.closest("[data-step]");
      if (!step) return;
      // it is inside the slot, and the slot's other job is to
      // open the chat on the note it is showing
      e.preventDefault();
      e.stopPropagation();
      this.go(this.at + Number(step.dataset.step));
    };
    this.el.addEventListener("click", this.onClick);

    // arrows, once the pager has been reached by keyboard
    this.onKey = (e) => {
      if (e.key === "ArrowLeft") this.go(this.at - 1);
      if (e.key === "ArrowRight") this.go(this.at + 1);
    };
    this.el.addEventListener("keydown", this.onKey);

    this.show();
  },

  // A patch can replace the cards — a note added, a note
  // superseded — so the index is re-applied rather than assumed,
  // and clamped in case the pile got shorter.
  updated() { this.show(); },

  destroyed() {
    this.el.removeEventListener("click", this.onClick);
    this.el.removeEventListener("keydown", this.onKey);
  },

  cards() { return [...this.el.querySelectorAll(".cards > .mg-note")]; },

  go(i) {
    const n = this.cards().length;
    if (!n) return;
    this.at = ((i % n) + n) % n;
    this.show();
  },

  show() {
    const cards = this.cards();
    if (!cards.length) return;
    this.at = Math.min(this.at, cards.length - 1);

    cards.forEach((c, i) => {
      const on = i === this.at;
      c.classList.toggle("on", on);
      // a hidden card is not a tab stop and is not read out
      c.setAttribute("aria-hidden", on ? "false" : "true");
      c.tabIndex = on ? 0 : -1;
    });

    const n = this.el.querySelector(".nav .n");
    if (n) n.textContent = `${this.at + 1} / ${cards.length}`;
  },
});
})();

/* ---- hooks/Editor.js ---- */
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

/* ---- hooks/Follow.js ---- */
(() => {
// The left column is read; the right one is driven.
//
// A focus line a third of the way down the left column decides what
// you are "on". Whichever linked paragraph last crossed it is the
// current one, and the right column is scrolled to put its
// counterpart at the same height. Reading is the input; nothing has
// to be clicked.
Blimp.hook("Follow", {
  // Every element this hook touches, looked up in one place.
  //
  // These used to be cached once in mounted() and never again.
  // A server re-render — dismissing the one-time card is enough —
  // can replace those nodes, and the hook then holds detached
  // ones: it adds the open class to a `.fl-mid` that is no longer
  // in the document, so a tap highlights the paragraph and the
  // reference never appears. Nothing throws, nothing logs, and
  // the feature is simply dead until reload.
  cache() {
    this.lead = this.el.querySelector("#fl-lead");
    this.other = this.el.querySelector("#fl-other");
    this.strip = this.el.querySelector(".fl-strip");
    this.sheet = this.el.querySelector(".fl-sheet");
    this.stack = this.el.querySelector(".fl-stack");
    this.svg = this.el.querySelector(".fl-wire");
    this.split = this.el.querySelector(".fl-split");
    this.idle = this.el.querySelector(".fl-idle");
    this.count = this.el.querySelector(".fl-count b");
    this.mid = this.el.querySelector(".fl-mid");
  },

  mounted() {
    this.cache();

    // clicking the line carries both passages into the chat;
    // delegated for the same reason as the sheet's controls
    this.onWireClick = (e) => {
      if (e.target.closest(".fl-wire .hit") && this.edge) {
        this.pushEvent("cite_edge", {edge: this.edge});
      }
    };
    this.el.addEventListener("click", this.onWireClick);

    // The chip's menu, in both columns. Delegated for the reason
    // everything else here is: a server patch replaces these nodes
    // and a listener bound to one of them stops working silently.
    this.onJump = (e) => {
      const item = e.target.closest(".fl-jump");
      if (item && !item.disabled) this.jump(item);
    };
    this.el.addEventListener("click", this.onJump);

    // Hovering an entry lights its far paragraph without committing
    // to it, so the menu answers "which three" before you pick one.
    this.onPeek = (e) => {
      const item = e.target.closest(".fl-jump");
      this.peek(item && !item.disabled ? item : null);
    };
    this.el.addEventListener("mouseover", this.onPeek);
    this.el.addEventListener("mouseout", this.onPeek);

    this.seen = new Set();
    this.current = null;

    this.onScroll = () => {
      if (this.queued) return;
      this.queued = true;
      requestAnimationFrame(() => { this.queued = false; this.follow(); });
    };

    this.lead.addEventListener("scroll", this.onScroll, {passive: true});
    // the right column moves under the wire too, by its own scroll
    // or by being driven, so it has to redraw as well
    this.other.addEventListener("scroll", () => this.wire(), {passive: true});

    // The two columns scroll; nothing else on the page does. That
    // leaves the strip between them — 17rem in the dead centre of
    // the screen, exactly where a cursor rests — and the bar at the
    // top as places where the wheel does nothing at all, which
    // reads as "this page will not scroll". Anywhere that is not a
    // column drives the one being read.
    this.onWheel = (e) => {
      if (e.target.closest(".fl-col")) return;
      this.lead.scrollTop += e.deltaY;
      e.preventDefault();
    };
    this.el.addEventListener("wheel", this.onWheel, {passive: false});
    // reading the right-hand document by hand should not be fought
    this.other.addEventListener("wheel", () => this.release(), {passive: true});
    window.addEventListener("resize", this.onScroll);

    // A tap on a highlighted passage picks it, rather than making
    // someone scroll it past the focus line. On a phone, where
    // the other column is not on screen at all, that is the only
    // way to point at something.
    this.onTap = (e) => {
      // the chip's menu picks one edge out of several; letting the
      // tap handler run too would immediately re-select the first
      if (e.target.closest(".fl-jump")) return;
      const block = e.target.closest(".fl-block.linked");
      if (!block) return;
      if (window.getSelection()?.toString()) return;
      this.current = block;
      this.free = false;
      this.mark(block);

      if (this.phone()) {
        if (this.fillStack(block)) {
          this.sheet.hidden = false;
          this.strip.hidden = true;
          this.stack.scrollTop = 0;
          this.openSheet();
        }
      } else {
        this.align(block);
      }
    };
    this.lead.addEventListener("click", this.onTap);

    this.onSheetKey = (e) => {
      if (e.key === "Escape" && this.mid?.classList.contains("open")) this.closeSheet();
    };
    document.addEventListener("keydown", this.onSheetKey);

    // Delegated, not bound to the nodes themselves: a patch can
    // replace them, and a listener on a node that is no longer in
    // the document is a control that silently stops working.
    this.onSheetClick = (e) => {
      // asking about it takes you into the chat, so the reference
      // gets out of the way rather than sitting on top of it
      // The stack's cards are created here, not rendered by the
      // server, so LiveView never bound their clicks — the hook
      // sends the event itself.
      const ask = e.target.closest(".fl-card .ask");
      if (ask) {
        if (ask.dataset.edge) this.pushEvent("cite_edge", {edge: ask.dataset.edge});
        return this.closeSheet();
      }

      // The strip's ask is the same gesture as clicking the drawn
      // line, so it sends the same event. It used to be a server
      // `phx-click` whose edge id the hook wrote on with
      // setAttribute — a server-owned attribute patched from JS,
      // paired with a handler clause that silently did nothing when
      // the attribute was missing. One path, pushed from here, is
      // both shorter and impossible to half-wire.
      const stripAsk = e.target.closest(".fl-strip .ask");
      if (stripAsk) {
        if (this.edge) this.pushEvent("cite_edge", {edge: this.edge});
        return;
      }

      if (e.target.closest(".shut")) {
        return this.closeSheet();
      }
      // the dimmed part, outside the sheet itself
      if (e.target.classList && e.target.classList.contains("fl-mid")) {
        return this.closeSheet();
      }
    };
    this.el.addEventListener("click", this.onSheetClick);

    this.follow();
  },

  updated() {
    // the patch may have swapped the nodes underneath us
    const wasOpen = this.mid?.classList.contains("open");
    this.cache();
    if (wasOpen) this.mid?.classList.add("open");

    this.seen.clear();
    this.current = null;
    this.follow();
  },

  destroyed() {
    document.documentElement.classList.remove("fl-sheet-open");
    document.removeEventListener("keydown", this.onSheetKey);
    this.lead.removeEventListener("click", this.onTap);
    this.el.removeEventListener("click", this.onSheetClick);
    this.el.removeEventListener("click", this.onWireClick);
    this.el.removeEventListener("click", this.onJump);
    this.el.removeEventListener("mouseover", this.onPeek);
    this.el.removeEventListener("mouseout", this.onPeek);
    this.lead.removeEventListener("scroll", this.onScroll);
    this.el.removeEventListener("wheel", this.onWheel);
    cancelAnimationFrame(this.frame);
    window.removeEventListener("resize", this.onScroll);
  },

  release() { this.free = true; },

  // A phone has no room for a second column and no room for a
  // permanent strip either: the screenshot that killed the last
  // design had six hundred pixels of chrome, a sliver of reading
  // and a sheet competing with it for the rest. So the reference
  // is a place you go and come back from.
  phone() { return window.matchMedia("(max-width: 1100px)").matches; },

  // The sheet scrolls, and it kept its position between passages,
  // so it opened halfway down the previous one. Defined here with
  // the other methods rather than as a closure in mounted(),
  // where deleting the code above it took this with it and left
  // mark() calling a function that no longer existed — which
  // threw after the highlight and before the sheet, so a tap lit
  // the paragraph and did nothing else.
  rewind() { if (this.strip) this.strip.scrollTop = 0; },

  // One card per connection on the tapped paragraph, in the order
  // the page has them. Built here rather than rendered by the
  // server because the server does not know which paragraph a
  // thumb landed on, and shipping every paragraph's stack up
  // front would be the whole document twice.
  fillStack(block) {
    const notes = [...block.querySelectorAll("[data-peer-ref]")];
    if (!notes.length) return false;

    this.sheet.querySelector(".n").textContent =
      notes.length === 1 ? "1 connection" : `${notes.length} connections`;

    this.stack.replaceChildren(
      ...notes.map((note) => {
        const card = document.createElement("article");
        card.className = `fl-card k-${note.dataset.kind}`;

        const peer = this.other.querySelector(
          `#blk-other-${CSS.escape(note.dataset.peerRef || "")}`
        );
        const prose = peer
          ? [...peer.querySelectorAll("p")].map((el) => el.textContent.trim()).join(" ")
          : "";

        const head = document.createElement("header");
        const rel = document.createElement("span");
        rel.className = "rel";
        rel.textContent = (note.dataset.kind || "").replace(/_/g, " ");
        const src = document.createElement("span");
        src.className = "src";
        src.textContent = note.dataset.src || "";
        head.append(rel, src);

        const why = document.createElement("p");
        why.className = "why";
        why.textContent = note.dataset.why || "";

        const ask = document.createElement("button");
        ask.type = "button";
        ask.className = "ask";
        ask.dataset.edge = note.dataset.edge || "";
        ask.textContent = "ask about this";

        card.append(head, why);

        if (prose) {
          const far = document.createElement("blockquote");
          far.className = "far";
          far.textContent = prose;
          card.append(far);
        }

        card.append(ask);
        return card;
      })
    );

    return true;
  },

  openSheet() {
    this.mid.classList.add("open");
    document.documentElement.classList.add("fl-sheet-open");
  },

  closeSheet() {
    this.mid.classList.remove("open");
    document.documentElement.classList.remove("fl-sheet-open");
  },

  // The linked paragraph you are currently on: the last one to have
  // crossed the focus line while still being on screen. The "still
  // on screen" half matters — without it a paragraph scrolled past
  // ten screens ago stays selected through every unlinked stretch,
  // and the right-hand column sits on something you cannot see.
  currentBlock() {
    const box = this.lead.getBoundingClientRect();
    const line = box.top + this.lead.clientHeight * 0.33;
    let passed = null;
    let upcoming = null;

    for (const b of this.lead.querySelectorAll(".fl-block.linked")) {
      const r = b.getBoundingClientRect();
      if (r.bottom < box.top || r.top > box.bottom) continue;
      if (r.top <= line) passed = b;
      else if (!upcoming) upcoming = b;
    }

    // nothing has crossed the line yet but something is coming: show
    // it rather than nothing, so the right column is never blank
    // while a link is plainly visible
    return passed || upcoming;
  },

  follow() {
    // nothing to follow with: the reference is not on screen and
    // the reader opens it deliberately
    if (this.phone()) return;

    // A jump from the right column scrolls the left one, and that
    // scroll fires this. Without the hold, follow() re-picks
    // whatever paragraph the smooth scroll is currently passing
    // and the pair you asked for is gone before it arrives.
    if (performance.now() < (this.hold || 0)) return;

    const block = this.currentBlock();
    if (!block) return this.blank();

    if (block !== this.current) {
      this.current = block;
      this.free = false;
      this.mark(block);
    }

    if (!this.free) this.align(block);
  },

  // One entry of the chip's menu. The button carries only the edge
  // id; the note itself is the hidden span already on the paragraph,
  // which is where every other path here reads a relation from.
  jump(item) {
    const edge = item.dataset.edge;
    const block = item.closest(".fl-block");
    const mine = block.querySelector(`[data-peer-ref][data-edge="${CSS.escape(edge)}"]`);
    if (!mine) return;

    this.peek(null);

    // Clicked in the left column: this paragraph is the near end,
    // and the right column comes to meet it.
    if (this.lead.contains(block)) {
      this.current = block;
      this.free = false;
      this.mark(block, mine);

      if (this.phone()) {
        if (this.fillStack(block)) {
          this.sheet.hidden = false;
          this.strip.hidden = true;
          this.stack.scrollTop = 0;
          this.openSheet();
        }
      } else {
        this.align(block, mine);
      }
      return;
    }

    // Clicked in the right column, where the far end is a paragraph
    // of the document being read. Go there rather than to it: the
    // left column is the one with the reading position in it.
    const ref = mine.dataset.peerRef;
    const target = ref && this.lead.querySelector(`#blk-lead-${CSS.escape(ref)}`);
    if (!target) return;

    const note =
      target.querySelector(`[data-peer-ref][data-edge="${CSS.escape(edge)}"]`) ||
      target.querySelector("[data-peer-ref]");

    const to =
      target.getBoundingClientRect().top -
      this.lead.getBoundingClientRect().top +
      this.lead.scrollTop -
      this.lead.clientHeight * 0.28;

    this.hold = performance.now() + 1200;
    this.lead.scrollTo({top: Math.max(0, to), behavior: "smooth"});

    this.current = target;
    this.free = false;
    this.mark(target, note);
    this.chase();
  },

  // The far paragraph of the entry under the cursor, lit but not
  // chosen. A class of its own: `on` is the committed pair, and
  // borrowing it would leave two pairs highlighted at once.
  peek(item) {
    this.el.querySelectorAll(".fl-block.peek").forEach((b) => b.classList.remove("peek"));
    if (!item) return;

    const here = item.closest(".fl-block");
    const far = this.lead.contains(here) ? this.other : this.lead;
    const side = far === this.other ? "other" : "lead";
    const ref = item.dataset.peerRef;
    if (!ref) return;

    far.querySelector(`#blk-${side}-${CSS.escape(ref)}`)?.classList.add("peek");
  },

  // `pick` is the specific edge to show. It defaults to the first
  // one on the paragraph, which is what scrolling past it means,
  // but a hub paragraph has several and the chip's menu names one.
  mark(block, pick) {
    const note = pick || block.querySelector("[data-peer-ref]");
    if (!note) return;

    this.lead.querySelectorAll(".fl-block.on").forEach((b) => b.classList.remove("on"));
    this.other.querySelectorAll(".fl-block.on").forEach((b) => b.classList.remove("on"));
    block.classList.add("on", "seen");

    const peer = this.other.querySelector(`#blk-other-${note.dataset.peerRef}`);
    peer?.classList.add("on");

    this.strip.hidden = false;
    this.idle.hidden = true;
    this.strip.dataset.kind = note.dataset.kind;
    this.strip.querySelector(".rel").textContent = note.dataset.kind.replace(/_/g, " ");
    this.strip.querySelector(".why").textContent = note.dataset.why;

    this.seen.add(note.dataset.edge);
    this.count.textContent = this.seen.size;
    this.strip.querySelector(".nth").textContent = note.dataset.src;

    // The passage on the other side, for the half of the screen a
    // phone does not have. The paragraphs only: the block also
    // holds the relation tag
    // and the hidden spans carrying this data, and on a phone the
    // column is display:none, where innerText falls back to
    // textContent and would sweep both of them in
    const far = this.strip.querySelector(".far");
    const prose = peer
      ? [...peer.querySelectorAll("p")].map((el) => el.textContent.trim()).join(" ")
      : "";
    far.textContent = prose;
    far.hidden = !prose;
    this.svg.dataset.kind = note.dataset.kind;
    // what the strip's ask button will cite, read at click time
    this.edge = note.dataset.edge;
    this.rewind();
    this.chase();
  },

  // the right column is scrolled smoothly, so the wire has to follow
  // it rather than be drawn once against where it used to be
  chase() {
    cancelAnimationFrame(this.frame);
    const until = performance.now() + 900;
    const step = () => {
      this.wire();
      if (performance.now() < until) this.frame = requestAnimationFrame(step);
    };
    step();
  },

  wire() {
    const l = this.lead.querySelector(".fl-block.on");
    const r = this.other.querySelector(".fl-block.on");
    if (!l || !r || this.strip.hidden) return this.svg.setAttribute("hidden", "");

    const box = this.split.getBoundingClientRect();
    const lb = l.getBoundingClientRect();
    const rb = r.getBoundingClientRect();
    const card = this.strip.getBoundingClientRect();
    const lc = this.lead.getBoundingClientRect();
    const rc = this.other.getBoundingClientRect();

    // a passage scrolled out of its own column is not connected to
    // anything the reader can see
    const on = (b, c) => b.bottom > c.top + 4 && b.top < c.bottom - 4;
    if (!on(lb, lc) || !on(rb, rc)) return this.svg.setAttribute("hidden", "");

    // below the sticky column head, so the line never runs under it
    const clamp = (y, c) => Math.max(c.top + 44, Math.min(y, c.bottom - 8));
    const y1 = clamp(lb.top + lb.height / 2, lc) - box.top;
    const y4 = clamp(rb.top + rb.height / 2, rc) - box.top;
    const ym = card.top + card.height / 2 - box.top;

    const x1 = lb.right - box.left;
    const x2 = card.left - box.left - 6;
    const x3 = card.right - box.left + 6;
    const x4 = rb.left - box.left;

    this.svg.removeAttribute("hidden");
    this.svg.setAttribute("viewBox", `0 0 ${box.width} ${box.height}`);
    const d1 = `M ${x1} ${y1} C ${(x1 + x2) / 2} ${y1}, ${(x1 + x2) / 2} ${ym}, ${x2} ${ym}`;
    const d2 = `M ${x3} ${ym} C ${(x3 + x4) / 2} ${ym}, ${(x3 + x4) / 2} ${y4}, ${x4} ${y4}`;
    this.svg.querySelector(".w1").setAttribute("d", d1);
    this.svg.querySelector(".w2").setAttribute("d", d2);
    this.svg.querySelector(".h1").setAttribute("d", d1);
    this.svg.querySelector(".h2").setAttribute("d", d2);
    this.svg.querySelector(".d1").setAttribute("cx", x1);
    this.svg.querySelector(".d1").setAttribute("cy", y1);
    this.svg.querySelector(".d2").setAttribute("cx", x4);
    this.svg.querySelector(".d2").setAttribute("cy", y4);
  },

  // put the cited passage at the same height as the one being read
  align(block, pick) {
    const note = pick || block.querySelector("[data-peer-ref]");
    const peer = note && this.other.querySelector(`#blk-other-${CSS.escape(note.dataset.peerRef || "")}`);
    if (!peer) return;

    // offsetTop is measured from the offsetParent, which is not the
    // scroll container — the two only agree by accident. Work in
    // viewport coordinates and add the scroll back on.
    const want = block.getBoundingClientRect().top - this.lead.getBoundingClientRect().top;
    const peerTop =
      peer.getBoundingClientRect().top -
      this.other.getBoundingClientRect().top +
      this.other.scrollTop;

    const to = Math.max(0, Math.min(peerTop - want, this.other.scrollHeight - this.other.clientHeight));

    if (Math.abs(this.other.scrollTop - to) > 2) {
      this.other.scrollTo({top: to, behavior: "smooth"});
    }
  },

  blank() {
    this.svg.setAttribute("hidden", "");
    this.strip.hidden = true;
    this.idle.hidden = false;
    this.lead.querySelectorAll(".fl-block.on").forEach((b) => b.classList.remove("on"));
    this.other.querySelectorAll(".fl-block.on").forEach((b) => b.classList.remove("on"));
    this.current = null;
  },
});
})();

/* ---- hooks/Hover.js ---- */
(() => {
// Hover to see a candidate in the line it would replace; the
// pointer leaving puts the line back. Debounced on the way out so
// moving between two candidates does not flicker the paragraph.
Blimp.hook("Hover", {
  mounted() {
    this.el.addEventListener("mouseover", (e) => {
      const row = e.target.closest(".mg-rw");
      if (!row) return;
      clearTimeout(this.out);
      if (row.dataset.i !== this.showing) {
        this.showing = row.dataset.i;
        this.pushEvent("preview_rewrite", {i: row.dataset.i});
      }
    });

    this.el.addEventListener("mouseleave", () => {
      clearTimeout(this.out);
      this.out = setTimeout(() => {
        this.showing = null;
        this.pushEvent("clear_preview", {});
      }, 80);
    });
  },
  destroyed() { clearTimeout(this.out); },
});
})();

/* ---- hooks/LaneTree.js ---- */
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

/* ---- hooks/LinkChat.js ---- */
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

/* ---- hooks/LinkChatComposer.js ---- */
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

/* ---- hooks/MarginNotes.js ---- */
(() => {
// Two layouts, one set of notes.
//
// Wide: each note sits level with its own highlight, measured and
// stacked so nothing overlaps. Grid rows cannot do this — they either
// tear holes in the prose or drop the alignment.
//
// Narrow, which is what the chat drawer leaves: there is no margin,
// and a rail squeezed into what remains is worse than none. So the
// notes fold back into the text. The highlight becomes the whole
// affordance — hover peeks, click pins. Pinning matters because
// reading a note and then going to write about it should not require
// holding the mouse still.
Blimp.hook("MarginNotes", {
  mounted() {
    this.pinned = new Set();
    this.showing = new Map();
    this.layout();
    this.watch();
  },
  updated() {
    // a morph may have replaced the highlights: point the open peeks
    // and pins at the current nodes, and drop the ones that are gone
    [...this.showing.keys()].forEach((ref) => {
      const mark = this.el.querySelector(`#anchor-${CSS.escape(ref)}`);
      if (mark) this.showing.set(ref, mark);
      else { this.showing.delete(ref); this.pinned.delete(ref); }
    });
    this.pinned.forEach((ref) =>
      this.el.querySelector(`#anchor-${CSS.escape(ref)}`)?.classList.add("pinned"));
    this.layout();
  },
  destroyed() {
    this.el.removeEventListener("mouseover", this.onOver);
    this.el.removeEventListener("mouseout", this.onOut);
    this.el.removeEventListener("click", this.onMarkClick);
    this.ro?.disconnect();
    document.removeEventListener("click", this.onAway);
    window.removeEventListener("scroll", this.onScroll, true);
    window.removeEventListener("resize", this.onScroll);
  },

  collapsed() { return this.el.classList.contains("collapsed"); },

  slotsFor(ref) {
    return [...this.el.querySelectorAll(`.mg-note-slot[data-anchor="${CSS.escape(ref)}"]`)];
  },

  watch() {
    this.ro = new ResizeObserver(() => this.layout());
    this.ro.observe(this.el);

    // Delegated on this.el, so notes and highlights the server adds or
    // replaces later are covered without rebinding. mouseenter/leave do
    // not bubble; mouseover/out do, so enter/leave is rebuilt from
    // relatedTarget.
    const markOf = (t) => t.closest?.(".mg-read-body mark[id]");
    const slotOf = (t) => t.closest?.(".mg-note-slot");
    const anchorMark = (slot) => {
      const id = slot.dataset.anchor;
      return id && this.el.querySelector(`#anchor-${CSS.escape(id)}`);
    };

    this.onOver = (e) => {
      const slot = slotOf(e.target);
      if (slot && !slot.contains(e.relatedTarget)) anchorMark(slot)?.classList.add("lit");
      const mark = markOf(e.target);
      if (mark && !mark.contains(e.relatedTarget) && this.collapsed())
        this.peek(mark.id.replace(/^anchor-/, ""), mark);
    };
    this.onOut = (e) => {
      const slot = slotOf(e.target);
      if (slot && !slot.contains(e.relatedTarget)) anchorMark(slot)?.classList.remove("lit");
      const mark = markOf(e.target);
      if (mark && !mark.contains(e.relatedTarget) && this.collapsed())
        this.unpeek(mark.id.replace(/^anchor-/, ""));
    };
    this.onMarkClick = (e) => {
      const mark = markOf(e.target);
      if (!mark || !this.collapsed()) return;
      const ref = mark.id.replace(/^anchor-/, "");
      e.stopPropagation();
      if (this.pinned.has(ref)) { this.pinned.delete(ref); this.unpeek(ref); }
      else { this.pinned.add(ref); this.peek(ref, mark); }
      mark.classList.toggle("pinned", this.pinned.has(ref));
    };
    this.el.addEventListener("mouseover", this.onOver);
    this.el.addEventListener("mouseout", this.onOut);
    this.el.addEventListener("click", this.onMarkClick);

    // a click anywhere else lets go of everything pinned
    this.onAway = (e) => {
      if (!this.collapsed()) return;
      if (e.target.closest(".mg-note-slot") || e.target.closest("mark[id]")) return;
      [...this.pinned].forEach((ref) => { this.pinned.delete(ref); this.unpeek(ref); });
      this.el.querySelectorAll("mark.pinned").forEach((m) => m.classList.remove("pinned"));
    };
    document.addEventListener("click", this.onAway);

    // follow the text: capture phase, so a scroll inside the drawer
    // or any other scrolling ancestor counts too
    let queued = false;
    this.onScroll = () => {
      if (queued || !this.showing.size) return;
      queued = true;
      requestAnimationFrame(() => { queued = false; this.reposition(); });
    };
    window.addEventListener("scroll", this.onScroll, true);
    window.addEventListener("resize", this.onScroll);
  },

  peek(ref, mark) {
    this.showing.set(ref, mark);
    this.slotsFor(ref).forEach((slot) => slot.classList.add("peek"));
    this.reposition();
  },

  unpeek(ref) {
    if (this.pinned.has(ref)) return;
    this.showing.delete(ref);
    this.slotsFor(ref).forEach((slot) => {
      slot.classList.remove("peek");
      slot.style.left = "";
      slot.style.top = "";
      slot.style.removeProperty("--caret");
    });
  },

  // Fixed positioning takes viewport coordinates, and the page scrolls
  // under them — so the note has to be put back against its highlight
  // on every scroll, or it is left behind the moment you move. This
  // runs on scroll and resize, rAF-throttled.
  // The notes on one highlight are laid out as a stack, not as
  // independent boxes. Clamping each one to the viewport separately
  // collapsed them onto the same `top` whenever the group did not
  // fit, so two notes landed on top of each other — the group is
  // measured and clamped once, then each note is placed from there.
  reposition() {
    const GAP = 8;

    this.showing.forEach((mark, ref) => {
      const r = mark.getBoundingClientRect();
      const slots = this.slotsFor(ref);
      if (!slots.length) return;

      // the highlight has scrolled away: take the note with it,
      // unless it is pinned
      const gone = r.bottom < 8 || r.top > window.innerHeight - 8;
      if (gone && !this.pinned.has(ref)) return this.unpeek(ref);

      const heights = slots.map((s) => s.offsetHeight);
      const total = heights.reduce((a, h) => a + h, 0) + GAP * (slots.length - 1);

      // below the line by default, above it when there is no room,
      // and clamped as one block so the stack never folds together
      const below = r.bottom + 10;
      const above = below + total > window.innerHeight - 12;
      let top = above ? r.top - total - 10 : below;
      top = Math.max(8, Math.min(top, window.innerHeight - total - 8));

      const width = slots[0].offsetWidth;
      const left = Math.max(12, Math.min(r.left, window.innerWidth - 12 - width));
      // the caret points back at the start of the span it is about
      const caret = Math.max(14, Math.min(r.left - left + 10, width - 20));

      slots.forEach((slot, i) => {
        slot.style.left = `${left}px`;
        slot.style.top = `${top}px`;
        slot.style.setProperty("--caret", `${caret}px`);
        slot.style.zIndex = `${55 + i}`;
        slot.classList.toggle("flipped", above);
        // only the note nearest the line gets the pointer
        slot.classList.toggle("tailed", above ? i === slots.length - 1 : i === 0);
        top += heights[i] + GAP;
      });
    });
  },

  layout() {
    const rail = this.el.querySelector(".mg-read-rail");
    if (!rail) return;

    // collapsed: the notes live in the highlights, nothing to place
    if (this.collapsed()) {
      rail.classList.remove("measured");
      rail.style.height = "";
      this.unshove();
      this.el.querySelectorAll(".mg-note-slot").forEach((s) => {
        if (!s.classList.contains("peek")) s.style.top = "";
      });
      return;
    }

    // back to the margin: drop anything left floating
    this.el.querySelectorAll(".mg-note-slot.peek").forEach((s) => {
      s.classList.remove("peek");
      s.style.left = "";
    });
    this.el.querySelectorAll("mark.pinned").forEach((m) => m.classList.remove("pinned"));
    this.pinned.clear();
    this.showing.clear();

    // one column is too narrow for a margin: fall back to flow
    if (getComputedStyle(this.el).gridTemplateColumns.split(" ").length < 3) {
      rail.classList.remove("measured");
      rail.style.height = "";
      this.unshove();
      this.el.querySelectorAll(".mg-note-slot").forEach((s) => (s.style.top = ""));
      return;
    }

    rail.classList.add("measured");
    const railTop = rail.getBoundingClientRect().top;
    let y = 0;

    this.el.querySelectorAll(".mg-note-slot").forEach((slot) => {
      const id = slot.dataset.anchor;
      const mark = id && this.el.querySelector(`#anchor-${CSS.escape(id)}`);
      const wanted = mark ? mark.getBoundingClientRect().top - railTop : y;
      const top = Math.max(wanted, y);
      slot.style.top = `${top}px`;
      y = top + slot.offsetHeight + 10;
    });

    rail.style.height = `${y}px`;
    this.shove(rail, railTop);
  },

  // An applied diff is as wide as all three columns and sits on
  // top of the rail, so the notes level with it are buried — and
  // the ones it buries are exactly the notes about the paragraph
  // that just changed. They move out past the prose, on the other
  // side, and come back when the diff is dismissed.
  //
  // There is less room out there than the note needs. The page is
  // 66ch of prose, a 3rem gutter and a 34ch rail, centred: at
  // 1512px that leaves 232px of margin against a 327px rail, and
  // on the 1000px-wide window this was reported from, 115px. So
  // the note goes as far left as the window allows and floats
  // over the left edge of the diff for the rest. Covering the
  // first few characters of a diff that is 100ch wide costs less
  // than burying the note about the paragraph that just changed,
  // which is what happens today.
  shove(rail, railTop) {
    const diff = this.el.querySelector(".mg-applied");
    if (!diff) return this.unshove();

    const slots = [...this.el.querySelectorAll(".mg-note-slot")];
    const body = this.el.querySelector(".mg-read-body");
    if (!slots.length || !body) return this.unshove();

    const d = diff.getBoundingClientRect();
    const b = body.getBoundingClientRect();
    const r = rail.getBoundingClientRect();

    const EDGE = 14;
    const TAIL = 18;
    // how close a note may come to the diff without being moved
    const CLEAR = 20;

    // Clear of the contents rail, which is fixed furniture down
    // the left of the window and would otherwise be drawn over
    // the first few words of every shoved note.
    const map = document.querySelector(".mg-map");
    const edge = Math.max(EDGE, map ? map.getBoundingClientRect().right + 10 : EDGE);

    const width = slots[0].offsetWidth;

    // in the rail's own coordinates, since that is what `left`
    // on an absolutely positioned slot is measured from
    const to = Math.max(edge, b.left - TAIL - width) - r.left;

    const band = {top: d.top - railTop, bottom: d.bottom - railTop};
    let floor = -Infinity;

    slots.forEach((slot) => {
      let top = parseFloat(slot.style.top) || 0;
      const high = slot.offsetHeight;

      // A third of the note, not a pixel of it. A card whose last
      // line grazes the top of the diff is still readable, and
      // sending it across the page for that is a worse jolt than
      // the overlap.
      const over = Math.min(top + high, band.bottom) - Math.max(top, band.top);
      const hits = over > high / 3;

      slot.classList.toggle("shoved", hits);
      // pinned in pixels rather than left to `right: auto`, or the
      // bubble collapses to its content width as it crosses
      slot.style.width = hits ? `${width}px` : "";
      slot.style.left = hits ? `${to}px` : "";

      // The near miss, which is the common one and the one that
      // looks like a bug: a card comes to rest with its last line
      // four pixels under the diff's top edge. Not worth sending
      // across the page, so it is moved clear the short way —
      // away from the diff, never into the card above it.
      if (!hits && top + high > band.top - CLEAR && top < band.bottom + CLEAR) {
        const above = top + high / 2 < (band.top + band.bottom) / 2;
        const want = above ? band.top - CLEAR - high : band.bottom + CLEAR;

        if (!above || want >= floor + 10) {
          top = want;
          slot.style.top = `${top}px`;
        }
      }

      floor = top + high;
    });
  },

  unshove() {
    this.el.querySelectorAll(".mg-note-slot.shoved").forEach((s) => {
      s.classList.remove("shoved");
      s.style.left = "";
      s.style.width = "";
    });
  },
});
})();

/* ---- hooks/Minimap.js ---- */
(() => {
// Open on click, and follow the reader down the page so the block
// beside where they are is lit. Kept client-side: which heading is
// on screen changes every few hundred milliseconds and is nobody's
// business but the browser's.
Blimp.hook("Minimap", {
  mounted() {
    this.links = [...this.el.querySelectorAll("a[data-target]")];
    this.rows = this.links.map((a) => a.parentElement);
    this.ticks = [...this.el.querySelectorAll(".mg-map-rail .t")];
    this.rail = this.el.querySelector(".mg-map-rail");

    this.rail.addEventListener("click", () => {
      const open = this.el.classList.toggle("open");
      this.rail.setAttribute("aria-expanded", open ? "true" : "false");
    });

    this.links.forEach((a, i) => {
      a.addEventListener("click", (e) => {
        e.preventDefault();
        const el = document.getElementById(a.dataset.target);
        if (el) el.scrollIntoView({behavior: "smooth", block: "start"});
        this.close();
        this.mark(i);
      });
    });

    // a click anywhere else closes it
    this.away = (e) => { if (!this.el.contains(e.target)) this.close(); };
    this.esc = (e) => { if (e.key === "Escape") this.close(); };
    document.addEventListener("click", this.away);
    document.addEventListener("keydown", this.esc);

    this.follow();
  },

  destroyed() {
    document.removeEventListener("click", this.away);
    document.removeEventListener("keydown", this.esc);
    this.io?.disconnect();
  },

  close() {
    this.el.classList.remove("open");
    this.rail.setAttribute("aria-expanded", "false");
  },

  mark(i) {
    this.ticks.forEach((t, j) => t.classList.toggle("on", j === i));
    this.rows.forEach((r, j) => r.classList.toggle("on", j === i));
  },

  follow() {
    const targets = this.links
      .map((a) => document.getElementById(a.dataset.target))
      .filter(Boolean);
    if (!targets.length) return;

    this.io = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          const i = targets.indexOf(entry.target);
          if (i >= 0) this.mark(i);
        }
      },
      // a band across the top: whatever has most recently passed it
      // is what the reader is in
      {rootMargin: "-10% 0px -80% 0px"}
    );

    targets.forEach((t) => this.io.observe(t));
  },
});
})();

/* ---- hooks/Reveal.js ---- */
(() => {
// Notes arrive as you reach the paragraph they annotate, and the worked
// examples play their turns in sequence once they're on screen. Both are
// one-shot: re-animating on every scroll past would be nauseating.
Blimp.hook("Reveal", {
  mounted() {
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const targets = this.el.querySelectorAll("[data-reveal], [data-demo]");

    if (reduce || !("IntersectionObserver" in window)) return;

    // Only now does anything hide. Without JS, or before this runs, the
    // page is fully readable — a landing page that needs JS to show its
    // own copy is a landing page that sometimes shows nothing.
    this.el.classList.add("reveal-ready");

    this.io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("in");
          if (entry.target.hasAttribute("data-demo")) this.play(entry.target);
          this.io.unobserve(entry.target);
        });
      },
      // fire a little before the top edge so the note is already there
      // by the time the eye arrives
      { rootMargin: "0px 0px -12% 0px", threshold: 0.15 }
    );

    targets.forEach((el) => this.io.observe(el));
  },

  // A demo is markup that already says what it means; the steps only
  // control WHEN each part of it appears, so the whole thing is legible
  // with the script dead or with motion turned down — the final frame is
  // the default state and `reveal-ready` is what hides it.
  play(demo) {
    const gap = parseInt(demo.dataset.interval || "650", 10);
    const steps = [...demo.querySelectorAll("[data-step]")].sort(
      (a, b) => Number(a.dataset.step) - Number(b.dataset.step)
    );

    this.timers = this.timers || [];

    steps.forEach((step, i) => {
      this.timers.push(
        setTimeout(() => step.classList.add("on"), gap * (i + 1))
      );
    });
  },

  destroyed() {
    if (this.io) this.io.disconnect();
    (this.timers || []).forEach(clearTimeout);
  },
});
})();

/* ---- hooks/Rotate.js ---- */
(() => {
// Three seconds a line, then out, swap, in. One line never rotates.
Blimp.hook("Rotate", {
  mounted() {
    this.lines = JSON.parse(this.el.dataset.lines || "[]");
    this.i = 0;
    if (this.lines.length < 2) return;
    this.timer = setInterval(() => {
      this.el.classList.add("out");
      this.swap = setTimeout(() => {
        this.i = (this.i + 1) % this.lines.length;
        this.el.textContent = this.lines[this.i];
        this.el.classList.remove("out");
      }, 320);
    }, 3000);
  },
  destroyed() {
    clearInterval(this.timer);
    clearTimeout(this.swap);
  },
});
})();

/* ---- hooks/Selection.js ---- */
(() => {
// Select a passage and both things you can do with it appear at the
// end of it: talk about that spot in its own thread, or carry it into
// the question you are already writing. Two different intentions, and
// guessing which one someone meant gets it wrong half the time.
//
// The text is verified against the manuscript server-side before
// either path keeps it: a browser selection picks up whatever the
// markup puts in its way.
Blimp.hook("Selection", {
  mounted() {
    this.bar = this.el.querySelector("#sel-actions");
    if (!this.bar) return;

    const act = (fn) => (e) => {
      // mousedown, not click: clicking clears the selection first
      e.preventDefault();
      const text = String(window.getSelection() || "").trim();
      const block = this.blockOf(window.getSelection());
      const endBlock = this.endBlockOf(window.getSelection());
      if (text.length >= 12) fn(text, block, endBlock);
      window.getSelection()?.removeAllRanges();
      this.hide();
    };

    this.bar.querySelector("#sel-add").addEventListener("mousedown", act((text) => {
      this.pushEvent("add_context", {text});
    }));

    this.bar.querySelector("#sel-rewrite").addEventListener("mousedown", act((text, block, endBlock) => {
      // The END of the selection, not the start. The panel renders
      // inside the block it names, so anchoring it to the first
      // paragraph of a four-paragraph drag put it above three
      // paragraphs of the thing it was rewriting and nowhere near
      // the cursor. The bar sits at the bottom of the range, so the
      // last block is where the mouse actually is.
      const at = endBlock || block;
      this.pushEvent("suggest_rewrite", {text, ref: at && at.ref});
    }));

    this.bar.querySelector("#sel-discuss").addEventListener("mousedown", act((text, block) => {
      if (!block) return;
      this.pushEvent("open_thread", {
        ref: block.ref,
        section: block.section,
        quote: text,
      });
    }));

    // Where the press landed, so a release can tell a click from a
    // drag. This is the whole reason the paragraph has no invisible
    // hit target over it any more: a <button> covering the prose
    // swallows the drag, and the owner — the only person who saw
    // that overlay — could not select a word of their own draft.
    this.onDown = (e) => { this.down = {x: e.clientX, y: e.clientY}; };
    this.onUp = (e) => {
      requestAnimationFrame(() => this.place());
      this.maybeEdit(e);
    };
    document.addEventListener("mousedown", this.onDown);
    document.addEventListener("mouseup", this.onUp);
    document.addEventListener("keyup", this.onUp);
    this.onScroll = () => this.hide();
    window.addEventListener("scroll", this.onScroll, {passive: true});
  },

  destroyed() {
    document.removeEventListener("mousedown", this.onDown);
    document.removeEventListener("mouseup", this.onUp);
    document.removeEventListener("keyup", this.onUp);
    window.removeEventListener("scroll", this.onScroll);
  },

  // A click inside your own prose opens the paragraph for editing; a
  // drag selects it. The two are told apart by whether anything got
  // selected and whether the pointer travelled, which is how every
  // text surface has always decided this.
  maybeEdit(e) {
    const body = this.el.querySelector(".mg-read-body");
    if (!body || body.dataset.editable !== "true") return;
    if (!e || typeof e.clientX !== "number" || !this.down) return;

    const sel = window.getSelection();
    if (sel && !sel.isCollapsed && String(sel).trim().length) return;
    if (Math.hypot(e.clientX - this.down.x, e.clientY - this.down.y) > 4) return;

    const block = e.target?.closest?.(".mg-block");
    if (!block || !body.contains(block)) return;

    // anything with its own job keeps it: the thread tick, a link in
    // the prose, an open thread or rewrite panel nested in the block
    if (e.target.closest("a, button, input, textarea, form, .mg-thread-panel, .mg-rewrite")) return;

    // A highlight is the note's own affordance — hover peeks,
    // click pins — so a click on one belongs to the margin, not
    // to the editor. With the drawer open that is the whole way
    // a passage gets fed to the conversation, and opening an
    // editor on top of it made adding a second one impossible.
    if (e.target.closest("mark[id]")) return;

    // and with the drawer open the draft is the reference, not
    // the thing being edited
    if (body.closest(".mg-read")?.classList.contains("collapsed")) return;

    this.pushEvent("edit_block", {ref: block.id.replace(/^block-/, "")});
  },

  // which paragraph the selection started in, so a thread can pin to it
  blockOf(sel) {
    if (!sel || !sel.rangeCount) return null;
    let node = sel.getRangeAt(0).startContainer;
    if (node.nodeType === Node.TEXT_NODE) node = node.parentElement;
    const el = node?.closest?.(".mg-block");
    if (!el) return null;
    const tick = el.querySelector(".mg-tick");
    return {ref: el.id.replace(/^block-/, ""), section: tick?.getAttribute("phx-value-section")};
  },

  // The last paragraph the selection actually covers, so the panel
  // opens where the drag finished rather than where it began.
  //
  // NOT endContainer. A drag that stops at the end of a paragraph
  // reports the NEXT node at offset 0 — the range ends *before* it,
  // covering none of it — so three highlighted paragraphs anchored
  // the panel under a fourth that was not selected at all. The
  // boundary comparisons below exclude a block the range merely
  // touches.
  endBlockOf(sel) {
    if (!sel || !sel.rangeCount) return null;
    const range = sel.getRangeAt(0);

    const covered = [...this.el.querySelectorAll(".mg-block")].filter((b) => {
      const br = document.createRange();
      br.selectNodeContents(b);
      // range ends at or before the block starts, or starts at or
      // after it ends: no text of this block is in the selection
      if (range.compareBoundaryPoints(Range.END_TO_START, br) >= 0) return false;
      if (range.compareBoundaryPoints(Range.START_TO_END, br) <= 0) return false;
      return true;
    });

    const el = covered[covered.length - 1];
    if (!el) return null;
    const tick = el.querySelector(".mg-tick");
    return {ref: el.id.replace(/^block-/, ""), section: tick?.getAttribute("phx-value-section")};
  },

  hide() { if (this.bar) this.bar.hidden = true; },

  place() {
    const sel = window.getSelection();
    const text = String(sel || "").trim();
    if (!sel || sel.isCollapsed || text.length < 12) return this.hide();

    const range = sel.getRangeAt(0);
    // only for the draft itself, not for the chat transcript
    if (!this.el.contains(range.commonAncestorContainer)) return this.hide();

    // The WHOLE range has to be in the prose, not just where it
    // started: dragging out of a paragraph and into a margin note
    // used to pass this check and then fail server-side, because the
    // note's words are not in the draft.
    //
    // Both ends, not the common ancestor. A selection inside one
    // paragraph has a text node for an ancestor and passed; a
    // selection across several has the container above them, which
    // is .mg-read-body itself or higher, and `contains` went false —
    // so the rewrite button vanished exactly when the span got
    // interesting. Testing the endpoints says what was meant.
    const body = this.el.querySelector(".mg-read-body");
    const inBody =
      body &&
      body.contains(range.startContainer) &&
      body.contains(range.endContainer);
    this.bar.querySelector("#sel-discuss").hidden = !inBody;
    this.bar.querySelector("#sel-rewrite").hidden = !inBody;

    const r = range.getBoundingClientRect();
    const host = this.el.getBoundingClientRect();
    this.bar.hidden = false;
    this.bar.style.top = `${r.bottom - host.top + 8}px`;
    this.bar.style.left = `${Math.max(0, r.left - host.left)}px`;
  },
});
})();

/* ---- hooks/Share.js ---- */
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

/* ---- hooks/Steer.js ---- */
(() => {
// The steering box grows with what is typed in it, up to a point.
//
// It was a one-line input, which is fine for "shorter" and wrong
// for the three-clause instruction people actually write: past
// the width of the box you are typing into a slot that shows you
// the last few words and hides the rest.
Blimp.hook("Steer", {
  mounted() {
    this.grow = () => {
      this.el.style.height = "auto";
      // capped, because this sits between the passage and the
      // candidates and should not push either off the screen
      this.el.style.height = Math.min(this.el.scrollHeight, 160) + "px";
    };

    this.onKey = (e) => {
      // Enter sends it; Shift+Enter is a newline, which is the
      // convention every chat box has taught everybody
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        this.el.form?.dispatchEvent(
          new Event("submit", {bubbles: true, cancelable: true})
        );
      }
    };

    this.el.addEventListener("input", this.grow);
    this.el.addEventListener("keydown", this.onKey);
    this.grow();
  },

  // phx-update="ignore" keeps what is half-typed through a patch,
  // so the height has to be re-measured here rather than on the
  // server's say-so
  updated() { this.grow(); },

  destroyed() {
    this.el.removeEventListener("input", this.grow);
    this.el.removeEventListener("keydown", this.onKey);
  },
});
})();

/* ---- hooks/StickDown.js ---- */
(() => {
// Where to put the scroll when an answer lands.
//
// Sticking to the bottom is right for short replies and wrong for
// long ones: it drops the reader at the last line of something they
// have not read a word of, and they have to scroll *up* to find the
// beginning. So a reply taller than the panel is snapped to its own
// top instead, and held there — no auto-scrolling while they read.
//
// The hold is released the moment they reach the end of it. From
// then on the panel sticks to the bottom again, which is what you
// want once you are caught up.
Blimp.hook("StickDown", {
  mounted() {
    this.bottom();
    this.el.addEventListener("scroll", () => this.check(), {passive: true});
  },

  updated() {
    const last = this.el.querySelector(".lc-turn.assistant:last-child");

    if (last && last !== this.seen) {
      this.seen = last;
      const room = this.el.clientHeight - 24;

      if (last.offsetHeight > room) {
        // start them at the first line of it
        this.holding = last;
        this.el.scrollTop = this.topOf(last) - 8;
        return;
      }

      this.holding = null;
      return this.bottom();
    }

    // a turn being added while they are caught up
    if (!this.holding && this.near()) this.bottom();
  },

  // the reader has read to the end of the held reply, so let go
  check() {
    if (!this.holding) return;
    const end = this.topOf(this.holding) + this.holding.offsetHeight;
    if (this.el.scrollTop + this.el.clientHeight >= end - 8) this.holding = null;
  },

  topOf(el) {
    return (
      el.getBoundingClientRect().top -
      this.el.getBoundingClientRect().top +
      this.el.scrollTop
    );
  },

  near() {
    return this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight < 120;
  },

  bottom() {
    this.el.scrollTop = this.el.scrollHeight;
  },
});
})();

/* ---- hooks/StickToBottom.js ---- */
(() => {
// Follow the conversation only while the reader is already at the
// bottom. Yanking someone back down mid-scroll while they are reading
// an earlier answer is the single most irritating thing a chat can do.
Blimp.hook("StickToBottom", {
  mounted() {
    this.pinned = true;
    this.el.addEventListener("scroll", () => {
      const gap = this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight;
      this.pinned = gap < 80;
    });
    this.toBottom("auto");
  },
  updated() { if (this.pinned) this.toBottom("smooth"); },
  toBottom(behavior) {
    requestAnimationFrame(() => this.el.scrollTo({top: this.el.scrollHeight, behavior}));
  },
});
})();

/* ---- hooks/SummaryVault.js ---- */
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

/* ---- hooks/Tree.js ---- */
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

/* ---- hooks/Walk.js ---- */
(() => {
// Spotlight one control, press it, wait for the page to answer, move
// on. The spotlight is a transparent box over the control with a
// very large shadow spread, so the lit thing keeps its own colours
// and everything else goes under a tint.
Blimp.hook("Walk", {
  mounted() {
    this.steps = JSON.parse(this.el.dataset.steps || "[]");
    this.i = -1;

    this.ring = this.el.querySelector(".mg-walk-ring");
    this.veil = this.el.querySelector(".mg-walk-veil");
    this.card = this.el.querySelector(".mg-walk-card");

    this.auto = this.el.dataset.auto || null;
    this.card.querySelector(".end").addEventListener("click", () => this.stop());
    this.card.querySelector(".next").addEventListener("click", () => this.go(this.i + 1));
    this.card.querySelector(".back").addEventListener("click", () => this.go(this.i - 1));

    // in auto mode the page always renders the overlay and the
    // button only asks it to run, so there is no round trip and
    // no account to remember it on
    this.onAsk = () => this.begin(true);
    this.el.addEventListener("mg:walk", this.onAsk);

    this.onKey = (e) => {
      if (e.key === "Escape") this.stop();
      if (e.key === "ArrowRight") this.go(this.i + 1);
      if (e.key === "ArrowLeft") this.go(this.i - 1);
    };
    document.addEventListener("keydown", this.onKey);

    // the target moves: panels open below it, the margin reflows,
    // the page scrolls. Re-measure rather than paint once.
    this.track = () => this.place();
    window.addEventListener("scroll", this.track, {passive: true});
    window.addEventListener("resize", this.track);
    this.timer = setInterval(this.track, 250);

    this.begin(false);
  },

  // `forced` is the button; otherwise it is a first visit
  begin(forced) {
    if (!this.auto) return this.go(0);

    const key = `mg.tour.${this.auto}`;
    let seen = false;
    try { seen = localStorage.getItem(key) === "1"; } catch (_) {}

    if (seen && !forced) return;

    try { localStorage.setItem(key, "1"); } catch (_) {}
    this.go(0);
  },

  // in auto mode the overlay stays in the DOM, so ending it is
  // the hook's job rather than the server's
  stop() {
    if (!this.auto) return this.pushEvent("end_walk", {});
    this.i = -1;
    this.card.hidden = true;
    this.ring.hidden = true;
    this.veil.hidden = true;
  },

  updated() {
    // a step's action re-renders the page; the element it lit may
    // have been replaced, so look it up again
    this.place();
  },

  destroyed() {
    document.removeEventListener("keydown", this.onKey);
    this.el.removeEventListener("mg:walk", this.onAsk);
    window.removeEventListener("scroll", this.track);
    window.removeEventListener("resize", this.track);
    clearInterval(this.timer);
  },

  go(i) {
    if (i < 0) return;
    if (i >= this.steps.length) return this.stop();

    this.i = i;
    const step = this.steps[i];

    this.card.querySelector("h3").textContent = step.title;
    this.card.querySelector(".body").textContent = step.body;
    this.card.querySelector(".n").textContent = `${i + 1} / ${this.steps.length}`;
    this.card.querySelector(".back").disabled = i === 0;
    this.card.querySelector(".next").textContent =
      i === this.steps.length - 1 ? "Done" : "Next";

    this.card.hidden = false;
    this.place();

    // let the spotlight land before the control is pressed, or the
    // reader never sees which one it was
    clearTimeout(this.actTimer);
    this.actTimer = setTimeout(() => this.act(step), 550);
  },

  act(step) {
    if (!step.act || this.i !== this.steps.indexOf(step)) return;

    if (step.act.kind === "push") {
      this.pushEvent(step.act.event, step.act.params || {});
    } else if (step.act.kind === "click") {
      // a control with no server event of its own: a details
      // summary, a link, the rail. Clicking it is what a reader
      // does, so the tour does the same thing.
      document.querySelector(step.act.target)?.click();
    } else if (step.act.kind === "hop") {
      // the cases are read across three views, and a tour that
      // stopped at a page boundary would be a tour of one page
      this.pushEvent("walk_hop", {to: step.act.to});
    } else {
      this.client(step.act.name);
    }
    setTimeout(() => this.place(), 260);
  },

  // Everything here goes through the real control: the tour clicks
  // what you would click. The only thing it does that you cannot is
  // make a text selection, which has no button.
  client(name) {
    const body = document.querySelector(".mg-read-body");
    const block = body && body.querySelector(".mg-block");

    if (name === "open_map") {
      const rail = document.querySelector(".mg-map-rail");
      if (rail && !document.querySelector(".mg-map").classList.contains("open")) rail.click();
      return;
    }

    if (name === "open_thread") {
      const tick = block && block.querySelector(".mg-tick");
      if (tick) tick.click();
      return;
    }

    if (name === "ask_thread") {
      const form = document.querySelector('form[phx-submit="thread_send"]');
      const box = form && form.querySelector("textarea, input[name=message]");
      if (!box) return;
      box.value = "What is this paragraph actually doing?";
      box.dispatchEvent(new Event("input", {bubbles: true}));
      form.dispatchEvent(new Event("submit", {bubbles: true, cancelable: true}));
      return;
    }

    if (name === "select") {
      const p = block && block.querySelector("p");
      if (!p) return;
      const range = document.createRange();
      range.selectNodeContents(p);
      const sel = window.getSelection();
      sel.removeAllRanges();
      sel.addRange(range);
      // the selection toolbar listens on the document, as a real
      // drag would end
      document.dispatchEvent(new MouseEvent("mouseup", {bubbles: true}));
      return;
    }

    if (name === "rewrite") {
      const btn = document.querySelector("#sel-rewrite");
      // it binds mousedown, because a click clears the selection first
      if (btn) btn.dispatchEvent(new MouseEvent("mousedown", {bubbles: true, cancelable: true}));
      return;
    }

    if (name === "edit") {
      if (block) this.pushEvent("edit_block", {ref: block.id.replace(/^block-/, "")});
      return;
    }

    if (name === "reset") {
      window.getSelection()?.removeAllRanges();
      document.querySelector(".mg-map")?.classList.remove("open");
      // the server holds the thread, the rewrite and the open editor
      this.pushEvent("walk_reset", {});
    }
  },

  target() {
    const step = this.steps[this.i];
    return step && step.target ? document.querySelector(step.target) : null;
  },

  place() {
    if (this.card.hidden) return;
    const el = this.target();

    if (!el) {
      // a step with nothing to point at — or a target that has not
      // rendered yet. Centre the card and drop the spotlight rather
      // than lighting the top-left corner of the page.
      this.ring.hidden = true;
      this.veil.hidden = false;
      this.card.className = "mg-walk-card centre";
      this.card.style.top = "";
      this.card.style.left = "";
      return;
    }

    const r = el.getBoundingClientRect();
    const pad = 6;
    const box = {
      top: r.top - pad, left: r.left - pad,
      width: r.width + pad * 2, height: r.height + pad * 2,
    };

    if (r.top < 90 || r.bottom > window.innerHeight - 60) {
      // the reading views scroll a column, not the window, and
      // scrollIntoView on a child of an overflow box moves that
      // box — which is exactly what is wanted here
      el.scrollIntoView({behavior: "smooth", block: "center"});
    }

    this.ring.hidden = false;
    this.veil.hidden = true;
    Object.assign(this.ring.style, {
      top: `${box.top}px`, left: `${box.left}px`,
      width: `${box.width}px`, height: `${box.height}px`,
    });

    this.card.className = "mg-walk-card";
    const cw = 22 * 16, gap = 16, m = 12;
    const ch = this.card.offsetHeight || 220;
    const W = window.innerWidth, H = window.innerHeight;

    // Candidates in the order the step asked for, then the rest.
    // A card that covers the thing it is pointing at defeats the
    // spotlight, so the clamped position is only taken when no
    // side fits — and even then it is the side with most room.
    const spots = {
      bottom: {left: box.left, top: box.top + box.height + gap},
      top: {left: box.left, top: box.top - ch - gap},
      right: {left: box.left + box.width + gap, top: box.top},
      left: {left: box.left - cw - gap, top: box.top},
    };

    const order = [this.steps[this.i].place || "right", "right", "left", "bottom", "top"];
    const fits = (p) =>
      p && p.left >= m && p.top >= m && p.left + cw <= W - m && p.top + ch <= H - m;

    let pick = order.map((k) => spots[k]).find(fits);

    if (!pick) {
      // no side fits whole; take the roomiest and clamp it, then
      // push it clear of the ring if it still overlaps
      const room = {
        bottom: H - (box.top + box.height), top: box.top,
        right: W - (box.left + box.width), left: box.left,
      };
      const best = Object.keys(room).sort((a, b) => room[b] - room[a])[0];
      pick = spots[best];
    }

    let left = Math.max(m, Math.min(pick.left, W - cw - m));
    let top = Math.max(m, Math.min(pick.top, H - ch - m));

    const over =
      left < box.left + box.width && left + cw > box.left &&
      top < box.top + box.height && top + ch > box.top;

    if (over) {
      // slide it to whichever side of the ring has the room
      left = box.left > W - (box.left + box.width)
        ? Math.max(m, box.left - cw - gap)
        : Math.min(W - cw - m, box.left + box.width + gap);
    }

    this.card.style.left = `${left}px`;
    this.card.style.top = `${top}px`;
  },
});
})();

/* ---- hooks/Weave.js ---- */
(() => {
// A member per row, and arcs between the pairs a claim rests on.
//
// While the read runs, the arcs shown are *candidates*: every pair of
// members, tried one at a time. That is not decoration — it is the
// question being asked, which is whether anything holds across two or
// more of these. When the answer lands the candidates stop and the
// pairs that actually held are drawn in, so the waiting state and the
// result are the same picture at two moments.
const ROW = 26, PAD = 12, GUT = 22;

Blimp.hook("Weave", {
  mounted() { this.draw(); },
  updated() { this.draw(); },
  destroyed() { this.stop(); },

  stop() {
    cancelAnimationFrame(this.frame);
    clearTimeout(this.timer);
    this.frame = this.timer = null;
  },

  draw() {
    this.stop();
    const members = JSON.parse(this.el.dataset.members || "[]");
    const links = JSON.parse(this.el.dataset.links || "[]");
    const reading = this.el.dataset.status === "reading";
    const svg = this.el.querySelector("svg");
    if (members.length < 2) { svg.innerHTML = ""; this.el.hidden = true; return; }

    const h = PAD * 2 + members.length * ROW;
    const w = 280;
    svg.setAttribute("viewBox", `0 0 ${w} ${h}`);
    svg.setAttribute("height", h);
    const y = (n) => PAD + (n - 1) * ROW + ROW / 2;

    const rows = members.map((m) => `
      <line class="cw-rule" x1="${GUT}" y1="${y(m.n)}" x2="${w - 8}" y2="${y(m.n)}"></line>
      <circle class="cw-dot" cx="${GUT}" cy="${y(m.n)}" r="3.2"></circle>
      <text class="cw-lbl" x="${GUT - 10}" y="${y(m.n) + 3.5}">${m.n}</text>`).join("");

    // The `d` alone, so both kinds of arc keep their class name as a
    // literal in the markup they build. A class that only exists as a
    // function argument is one nothing can check for.
    const curve = (a, b) => {
      const y1 = y(a), y2 = y(b);
      const bulge = Math.min(46, 14 + Math.abs(y1 - y2) * 0.42);
      return `M ${GUT} ${y1} C ${GUT + bulge} ${y1}, ${GUT + bulge} ${y2}, ${GUT} ${y2}`;
    };

    svg.innerHTML = rows + links.map((l) =>
      `<path class="cw-arc k-${l.kind}" fill="none" d="${curve(l.a, l.b)}"></path>`
    ).join("");

    // draw the settled arcs in, once
    svg.querySelectorAll(".cw-arc").forEach((p, i) => {
      const len = p.getTotalLength();
      p.style.strokeDasharray = len;
      p.style.strokeDashoffset = len;
      p.style.animation = `cw-draw .7s ease ${0.1 + i * 0.09}s forwards`;
    });

    if (reading) this.tryPairs(svg, members, curve);
  },

  // Every pair, in order, on a loop. The order is fixed rather than
  // random so two people watching the same folder see the same thing.
  tryPairs(svg, members, curve) {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const pairs = [];
    for (let i = 0; i < members.length; i++)
      for (let j = i + 1; j < members.length; j++)
        pairs.push([members[i].n, members[j].n]);

    let k = 0;
    const step = () => {
      svg.querySelectorAll(".cw-try").forEach((n) => n.remove());
      const [a, b] = pairs[k % pairs.length];
      svg.insertAdjacentHTML(
        "beforeend",
        `<path class="cw-try" fill="none" d="${curve(a, b)}"></path>`
      );
      const p = svg.querySelector(".cw-try");
      const len = p.getTotalLength();
      p.style.setProperty("--len", len);
      p.style.strokeDasharray = len;
      p.style.strokeDashoffset = len;
      p.style.animation = "cw-try 1.15s ease-in-out forwards";
      [a, b].forEach((n) => {
        const dot = svg.querySelectorAll(".cw-dot")[n - 1];
        if (dot) { dot.classList.remove("lit"); void dot.offsetWidth; dot.classList.add("lit"); }
      });
      k++;
      this.timer = setTimeout(step, 1250);
    };
    step();
  },
});
})();

/* ---- hooks/Wiring.js ---- */
(() => {
// Two columns of real nodes, and arcs tried between them. Nothing
// here is a result — see the note under it — it is the shape of the
// work, drawn while the work happens.
Blimp.hook("Wiring", {
  mounted() {
    this.a = JSON.parse(this.el.dataset.a || "[]");
    this.b = JSON.parse(this.el.dataset.b || "[]");
    this.svg = this.el.querySelector(".lw-svg");
    this.arcs = this.svg.querySelector(".arcs");
    this.dots = this.svg.querySelector(".dots");
    this.now = {l: this.el.querySelector(".lw-now .l"), r: this.el.querySelector(".lw-now .r")};

    if (!this.a.length || !this.b.length) return;
    // the dots are already on the page; motion is all this adds
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    this.tick = setInterval(() => this.tryPair(), 900);
    this.tryPair();
  },

  destroyed() { clearInterval(this.tick); },

  // mirrors y/2 in the component — the dots are placed server-side
  // and the arcs have to arrive at the same coordinates
  y(i, n) { return 30 + (i * (300 / Math.max(n - 1, 1))); },

  tryPair() {
    const ns = "http://www.w3.org/2000/svg";
    const i = Math.floor(Math.random() * this.a.length);
    const j = Math.floor(Math.random() * this.b.length);
    const y1 = this.y(i, this.a.length);
    const y2 = this.y(j, this.b.length);

    const path = document.createElementNS(ns, "path");
    path.setAttribute("d", `M 90 ${y1} C 300 ${y1}, 380 ${y2}, 590 ${y2}`);
    path.setAttribute("class", "arc");
    this.arcs.appendChild(path);

    // draw it on, hold, fade it out — then take it away entirely, so
    // nothing accumulates that could be mistaken for a result
    const len = path.getTotalLength();
    path.style.strokeDasharray = len;
    path.style.strokeDashoffset = len;
    path.getBoundingClientRect();
    path.style.transition = "stroke-dashoffset .7s ease-out, opacity .5s ease-in .9s";
    path.style.strokeDashoffset = 0;
    path.style.opacity = 0;
    setTimeout(() => path.remove(), 1800);

    this.lightUp("a", i);
    this.lightUp("b", j);
    this.now.l.textContent = this.a[i];
    this.now.r.textContent = this.b[j];
  },

  lightUp(side, i) {
    const dot = this.dots.querySelector(`circle[data-side="${side}"][data-i="${i}"]`);
    if (!dot) return;
    dot.classList.add("lit");
    setTimeout(() => dot.classList.remove("lit"), 1200);
  },
});
})();

