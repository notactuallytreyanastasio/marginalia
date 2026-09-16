defmodule MarginaliaWeb.LinkChat do
  @moduledoc """
  The chat about a pair of drafts: a bubble, and the panel it opens.

  Both link views carry it, so it lives here rather than twice. The state is
  the conversation, which is in the database — closing the panel puts it
  away, it does not throw it out, and reopening picks up mid-sentence.
  """
  use MarginaliaWeb, :html

  attr :open, :boolean, default: false
  attr :history, :list, default: []
  attr :thinking, :boolean, default: false
  attr :count, :integer, default: 0

  def bubble(assigns) do
    ~H"""
    <div class="lc" id="linkchat" phx-hook=".LinkChat">
      <button
        class={["lc-bubble", @open && "on"]}
        phx-click="toggle_chat"
        aria-label="Talk about how these two relate"
        title="Talk about how these two relate"
      >
        <span class="mark" aria-hidden="true">↔</span>
        <span :if={@count > 0 and not @open} class="n">{@count}</span>
      </button>

      <div :if={@open} class="lc-panel" role="dialog" aria-label="About this pair">
        <div class="lc-head">
          <span class="mg-label">About this pair</span>
          <button class="lc-x" phx-click="toggle_chat" aria-label="Close">×</button>
        </div>

        <div class="lc-body" id="lc-body" phx-hook=".StickDown">
          <p :if={@history == []} class="lc-hint">
            This one holds both maps and every edge between them. Ask what the second draft
            already answers, where the disagreement is real, or which connection is doing
            the most work. It will not write for either of them.
          </p>

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

        <form class="lc-foot" phx-submit="chat_send" id="lc-form" phx-hook=".Composer">
          <textarea
            name="message"
            rows="2"
            placeholder="How do these two sit together?"
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

      <script :type={Phoenix.LiveView.ColocatedHook} name=".StickDown">
        // stay at the newest turn unless the reader has scrolled up to read
        export default {
          mounted() { this.bottom(); },
          updated() { if (this.near()) this.bottom(); },
          near() { return this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight < 120; },
          bottom() { this.el.scrollTop = this.el.scrollHeight; },
        };
      </script>
    </div>
    """
  end
end
