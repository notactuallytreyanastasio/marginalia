defmodule MarginaliaWeb.Walk do
  @moduledoc """
  The guided run: spotlight a control, press it, let the page answer.

  This was inside the work page, which is where it was first needed and
  the wrong place for it to live — the cases are read across three
  different views and a tour that stops at a page boundary is not a tour
  of anything. One implementation, shared.

  A step is a map: `target` is a selector to light, `place` says which
  side the card goes, and `act` is what to do once the spotlight has
  landed. Three kinds of act:

    * `push` — send an event to the LiveView, which is what a click on a
      `phx-click` control does anyway;
    * `client` — work a control that has no server event, by name;
    * `hop` — leave for another page and carry on there.

  Everything goes through the real control. The tour clicks what you
  would click, so a step that stops working is a feature that broke, and
  that is the point of building it this way rather than as a video.
  """
  use MarginaliaWeb, :html

  attr :steps, :list, required: true

  # When set, the overlay decides for itself whether to run, against a
  # flag in the browser rather than a column on an account.
  #
  # "Has this person seen the tour" is a fact about a browser, not about
  # a user — and making it a user fact meant the public cases page had to
  # mint a throwaway account for every visitor just to remember it, which
  # is how 762 accounts came to serve five people. A page in auto mode
  # needs no account at all.
  attr :auto, :string, default: nil

  @doc false
  # What the card says about itself, all the way through. The manuscript
  # tour has to promise that nothing is written and no model is called,
  # because it is running on somebody's own draft and its answers are
  # fixtures. The cases tour must not say that: those documents are
  # public record and their readings are real, and telling a reader that
  # what they are looking at is a fixed example would be a false
  # statement about real output — the exact failure the promise exists
  # to prevent.
  attr :note, :string,
    default: "Nothing here is saved, and no model is called — the answers are fixed examples."

  # The spotlight and the card that walks it.
  #
  # The steps are handed over as data rather than driven from the server one
  # render at a time: the hook needs to measure an element, scroll to it and
  # follow it while the page reflows, all of which is per-frame work and none
  # of which is any of the server's business. What does cross the wire is
  # each step's action, as the ordinary event the control itself would send —
  # so the tour exercises the real handlers, and a step that breaks because
  def overlay(assigns) do
    ~H"""
    <div id="walk" phx-hook=".Walk" data-steps={Jason.encode!(@steps)} data-auto={@auto}>
      <div class="mg-walk-ring" hidden></div>
      <div class="mg-walk-veil" hidden></div>

      <div class="mg-walk-card" hidden>
        <div class="mg-walk-head">
          <span class="mg-label">Walkthrough</span>
          <span class="n"></span>
          <button class="mg-btn sm ghost ml-auto end">end</button>
        </div>
        <h3></h3>
        <p class="body"></p>
        <div class="mg-walk-foot">
          <button class="mg-btn sm ghost back">Back</button>
          <button class="mg-btn sm next">Next</button>
        </div>
        <p class="mg-walk-safe">{@note}</p>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".Walk">
        // Spotlight one control, press it, wait for the page to answer, move
        // on. The spotlight is a transparent box over the control with a
        // very large shadow spread, so the lit thing keeps its own colours
        // and everything else goes under a tint.
        export default {
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
        };
      </script>
    </div>
    """
  end

end
