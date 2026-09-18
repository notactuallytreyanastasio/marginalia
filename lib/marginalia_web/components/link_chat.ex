defmodule MarginaliaWeb.LinkChat do
  @moduledoc """
  The chat about related drafts: a bubble, and the panel it opens.

  Both link views carry it, so it lives here rather than twice. The state is
  the conversation, which is in the database — closing the panel puts it
  away, it does not throw it out, and reopening picks up mid-sentence.

  The copy is passed in because the same panel now answers two different
  questions: on a pair it is about how two documents sit together, and on
  a whole case it is about four or five of them at once. A panel headed
  "About this pair" over a chat that holds the dissent and three
  advocates is telling the reader something untrue about what it knows.
  """
  use MarginaliaWeb, :html

  attr :open, :boolean, default: false
  attr :history, :list, default: []
  attr :thinking, :boolean, default: false
  attr :count, :integer, default: 0
  attr :cited, :list, default: []
  attr :title, :string, default: "About this pair"
  attr :label, :string, default: "Talk about how these two relate"

  attr :hint, :string,
    default:
      "This one holds both maps and every edge between them. Ask what the second draft " <>
        "already answers, where the disagreement is real, or which connection is doing " <>
        "the most work. It will not write for either of them."

  attr :placeholder, :string, default: "How do these two sit together?"

  # Somewhere to start. An empty chat asks you to compose a question
  # about a relationship you have not read yet, which is hard on a
  # desktop and harder on a phone, where the cost of typing is the
  # reason people do not.
  attr :openers, :list,
    default: [
      "What does the second document already answer?",
      "Which disagreement here is real, and which is vocabulary?",
      "Which connection is doing the most work?"
    ]

  def bubble(assigns) do
    ~H"""
    <div class="lc" id="linkchat" phx-hook=".LinkChat">
      <button
        class={["lc-bubble", @open && "on"]}
        phx-click="toggle_chat"
        aria-label={@label}
        title={@label}
      >
        <span class="mark" aria-hidden="true">↔</span>
        <span :if={@count > 0 and not @open} class="n">{@count}</span>
      </button>

      <div :if={@open} class="lc-panel" role="dialog" aria-label={@title}>
        <div class="lc-head">
          <span class="mg-label">{@title}</span>
          <button class="lc-x" phx-click="toggle_chat" aria-label="Close">×</button>
        </div>

        <div class="lc-body" id="lc-body" phx-hook=".StickDown">
          <p :if={@history == []} class="lc-hint">
            {@hint}
          </p>

          <div :if={@history == [] and @openers != []} class="lc-openers">
            <button :for={q <- @openers} type="button" phx-click="chat_send" phx-value-message={q}>
              {q}
            </button>
          </div>

          <div :for={m <- @history} class={["lc-turn", m["role"]]}>
            <span class="who">{if m["role"] == "user", do: "you", else: "the reader"}</span>
            <div class="said md">
              {if m["role"] == "user",
                do: m["content"],
                else: Marginalia.Markdown.to_html(m["content"])}
            </div>
          </div>

          <div :if={@thinking} class="mg-dots" aria-label="reading">
            <span class="mg-dot"></span>
            <span class="mg-dot" style="animation-delay:.18s"></span>
            <span class="mg-dot" style="animation-delay:.36s"></span>
          </div>
        </div>

        <%!-- what the reader pointed at. Both passages go to the model in
              full, so these are not decoration — removing one removes it
              from the question. --%>
        <div :if={@cited != []} class="lc-cited">
          <span class="mg-label">pointing at</span>
          <div :for={e <- @cited} class={["chip", e.edge_type]}>
            <span class="rel">{String.replace(e.edge_type, "_", " ")}</span>
            <span class="t">{e.from.title} ↔ {e.to.title}</span>
            <button phx-click="uncite" phx-value-edge={e.id} aria-label="Remove">×</button>
          </div>
        </div>

        <form class="lc-foot" phx-submit="chat_send" id="lc-form" phx-hook=".Composer">
          <textarea
            name="message"
            rows="2"
            placeholder={@placeholder}
            disabled={@thinking}
          ></textarea>
          <div class="row">
            <span class="mg-hint mt-0">Enter to send</span>
            <button type="submit" class="mg-btn sm" disabled={@thinking}>Ask</button>
          </div>
        </form>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".LinkChat">
        // Click anywhere outside the panel and it puts itself away. The
        // conversation is server-side, so this loses nothing — reopening
        // comes back to the same place.
        export default {
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
        };
      </script>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".Composer">
        // Enter sends; shift-Enter is a newline. The form said "Enter to
        // send" and named this hook, and the hook was never written — so
        // LiveView threw `unknown hook` on the client, the binding for
        // the form never attached, and the panel opened, took typing and
        // sent nothing. Server-side tests cannot see that: they do not
        // run the hooks.
        export default {
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
        };
      </script>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".StickDown">
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
        export default {
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
        };
      </script>
    </div>
    """
  end
end
