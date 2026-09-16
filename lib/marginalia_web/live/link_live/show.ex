defmodule MarginaliaWeb.LinkLive.Show do
  @moduledoc """
  Two drafts side by side, with the graph drawn between them.

  The split is the whole idea. A relationship between two documents is not
  readable as a list of edges — "A §3 develops B §1" tells you a fact and
  shows you nothing. It is readable when the two passages are next to each
  other on the screen, which is what this does: click an annotation and the
  other column snaps so its paragraph sits level with yours, and the pair
  can be read across.

  Everything on the page comes from the link graph. The margin notes are the
  edges, placed on the paragraph whose sentence the near end was anchored to,
  which means the same rule that governs a note inside one draft governs a
  note between two: it sits beside the line that caused it, or it does not
  appear on the page at all.
  """
  use MarginaliaWeb, :live_view

  alias Marginalia.{Links, Reading}
  alias Marginalia.Links.Chat, as: LinkChat
  alias Marginalia.Analysis.Linker

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Links.get(id) do
      nil ->
        {:ok, socket |> put_flash(:error, "No such link.") |> push_navigate(to: ~p"/works")}

      link ->
        if connected?(socket), do: Phoenix.PubSub.subscribe(Marginalia.PubSub, "link:#{link.id}")
        {:ok, load(socket, link)}
    end
  end

  defp load(socket, link) do
    {a, b} = Links.works(link)
    {page_a, page_b} = Links.pages(link)

    assign(socket,
      chat_open: Map.get(socket.assigns, :chat_open, false),
      chat_thinking: Map.get(socket.assigns, :chat_thinking, false),
      chat_history: chat_history(link),
      chat_convo: Map.get(socket.assigns, :chat_convo),
      page_title: "#{a.title} ↔ #{b.title}",
      page_robots: "noindex, nofollow",
      link: link,
      a: a,
      b: b,
      page_a: page_a,
      page_b: page_b,
      edges: Links.edges(link),
      stats: Links.stats(link),
      only: nil,
      open: nil
    )
  end

  @impl true
  def handle_event("set_only", %{"only" => only}, socket) do
    {:noreply, assign(socket, only: if(only in ["", "all"], do: nil, else: only))}
  end

  # The click that makes the split worth having. The server only records
  # which edge is open; the snapping is the browser's job, because it is
  # measurement and scrolling and none of it is state worth a round trip.
  def handle_event("open_edge", %{"edge" => id}, socket),
    do: {:noreply, assign(socket, open: arg_int(id))}

  def handle_event("close_edge", _params, socket), do: {:noreply, assign(socket, open: nil)}

  def handle_event("relink", _params, socket) do
    Linker.start(socket.assigns.link)
    {:noreply, put_flash(socket, :info, "Reading both graphs again.")}
  end

  # --- the chat about this pair ---------------------------------------------

  def handle_event("toggle_chat", _params, socket),
    do: {:noreply, assign(socket, chat_open: !socket.assigns.chat_open)}

  def handle_event("close_chat", _params, socket),
    do: {:noreply, assign(socket, chat_open: false)}

  def handle_event("chat_send", %{"message" => text}, socket) do
    text = String.trim(text)
    a = socket.assigns

    if text == "" or a.chat_thinking do
      {:noreply, socket}
    else
      {:ok, convo} = LinkChat.conversation(a.link)
      {:ok, _} = LinkChat.append(convo, "user", text)

      history = LinkChat.history(convo)
      link = a.link

      {:noreply,
       socket
       |> assign(chat_history: history, chat_thinking: true, chat_convo: convo)
       |> start_async(:chat, fn -> LinkChat.ask(link, history) end)}
    end
  end

  @impl true
  def handle_info({:link, :done}, socket),
    do: {:noreply, load(socket, Links.get(socket.assigns.link.id))}

  def handle_info({:link, _}, socket),
    do: {:noreply, assign(socket, link: Links.get(socket.assigns.link.id))}

  defp arg_int(v) when is_integer(v), do: v

  defp arg_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} -> i
      :error -> nil
    end
  end

  defp arg_int(_), do: nil

  defp shown?(_note, nil), do: true
  defp shown?(note, only), do: note.kind == only

  @impl true
  def handle_async(:chat, {:ok, {:ok, reply}}, socket) do
    {:ok, _} = LinkChat.append(socket.assigns.chat_convo, "assistant", reply)

    {:noreply,
     assign(socket,
       chat_thinking: false,
       chat_history: LinkChat.history(socket.assigns.chat_convo)
     )}
  end

  def handle_async(:chat, {:ok, {:error, reason}}, socket),
    do: {:noreply, socket |> assign(chat_thinking: false) |> failed(reason)}

  def handle_async(:chat, {:exit, reason}, socket),
    do: {:noreply, socket |> assign(chat_thinking: false) |> failed(reason)}

  defp failed(socket, reason),
    do: put_flash(socket, :error, "That did not go through: #{inspect(reason)}")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} bleed>
      <%!-- Landed here straight from the Link button: the pass is still
            running. The page is subscribed, so it fills in by itself. --%>
      <div :if={@link.status in ["pending", "linking"]} class="lk-wait">
        <div class="mg-dots" aria-label="reading both graphs">
          <span class="mg-dot"></span>
          <span class="mg-dot" style="animation-delay:.18s"></span>
          <span class="mg-dot" style="animation-delay:.36s"></span>
        </div>
        <h2>Relating the two maps</h2>
        <p>
          <strong>{@a.title}</strong> and <strong>{@b.title}</strong>. It is reading both
          graphs — every beat, the spine, the threads — and drawing the edges between them.
          A minute or two. This page fills in on its own.
        </p>
      </div>

      <div :if={@link.status == "failed"} class="lk-wait">
        <h2>That did not go through</h2>
        <p>{@link.error}</p>
        <button class="mg-btn sm" phx-click="relink">Try again</button>
      </div>

      <div :if={@link.status == "linked"} class="lk" id="split" phx-hook=".Tandem">
        <%!-- One row. The two titles were here as a heading and again at the
              top of each column, and the summary took six lines of the thing
              the page exists to show. It is a clamped line that opens on
              click — <details>, so no JavaScript and no assign for it. --%>
        <div class="lk-head">
          <details :if={@link.summary} class="lk-sum">
            <summary>
              <span class="mg-label">linked</span>
              <span class="peek">{@link.summary}</span>
              <span class="more" aria-hidden="true"></span>
            </summary>
            <p>{@link.summary}</p>
          </details>

          <div class="fl-tabs">
            <span class="mg-tab on">Split</span>
            <.link navigate={~p"/links/#{@link.id}/read"} class="mg-tab">Read through</.link>
          </div>

          <div class="lk-legend">
            <button
              :for={{id, label} <- [{"all", "Everything"} | types(@stats)]}
              class={"mg-tab" <> if((@only || "all") == id, do: " on", else: "")}
              phx-click="set_only"
              phx-value-only={id}
            >{label}</button>
          </div>
        </div>

        <div class="lk-split">
          <.column
            side="a"
            work={@a}
            page={@page_a}
            only={@only}
            open={@open}
            peer="b"
          />
          <%!-- the wire. A pair of highlighted paragraphs is two facts; a
                line between them is one relationship, which is the thing
                this page is for. --%>
          <div class="lk-gutter" aria-hidden="true">
            <svg class="lk-wire" hidden>
              <path class="w" fill="none" />
              <circle class="a" r="3.5" />
              <circle class="b" r="3.5" />
            </svg>
          </div>
          <.column
            side="b"
            work={@b}
            page={@page_b}
            only={@only}
            open={@open}
            peer="a"
          />
        </div>
      </div>

      <MarginaliaWeb.LinkChat.bubble
        open={@chat_open}
        history={@chat_history}
        thinking={@chat_thinking}
        count={length(@chat_history)}
      />

      <script :type={Phoenix.LiveView.ColocatedHook} name=".Tandem">
        // Click an annotation and the two columns are brought level: the
        // paragraph it sits on and the paragraph it points at end up at the
        // same height, so the pair can be read across rather than
        // remembered across.
        export default {
          mounted() {
            this.svg = this.el.querySelector(".lk-wire");
            this.path = this.svg.querySelector(".w");
            this.dotA = this.svg.querySelector(".a");
            this.dotB = this.svg.querySelector(".b");

            this.el.addEventListener("click", (e) => {
              const note = e.target.closest("[data-peer-ref]");
              if (!note) return;
              this.tandem(note);
            });

            // The columns scroll and nothing else does, so the gutter and
            // the header are dead to the wheel — which reads as a page that
            // will not scroll. Send those to the left-hand column.
            this.onWheel = (e) => {
              if (e.target.closest(".lk-col")) return;
              const col = this.el.querySelector(".lk-col");
              if (!col) return;
              col.scrollTop += e.deltaY;
              e.preventDefault();
            };
            this.el.addEventListener("wheel", this.onWheel, {passive: false});

            // the wire is drawn from live positions, so any scroll moves it
            this.redraw = () => this.wire();
            this.el.querySelectorAll(".lk-col").forEach((c) =>
              c.addEventListener("scroll", this.redraw, {passive: true})
            );
            window.addEventListener("resize", this.redraw);
          },

          destroyed() {
            window.removeEventListener("resize", this.redraw);
            this.el.removeEventListener("wheel", this.onWheel);
            cancelAnimationFrame(this.frame);
          },

          // follow the smooth scroll for as long as it lasts
          chase() {
            cancelAnimationFrame(this.frame);
            const until = performance.now() + 900;
            const step = () => {
              this.wire();
              if (performance.now() < until) this.frame = requestAnimationFrame(step);
            };
            step();
          },

          show(on) {
            // SVGElement has no `hidden` property — only HTMLElement does.
            // Setting `svg.hidden = true` sets an expando that nothing reads
            // and nothing hides, which is exactly how a wire that was never
            // once drawn passed a probe that asked `!svg.hidden`.
            if (on) this.svg.removeAttribute("hidden");
            else this.svg.setAttribute("hidden", "");
            this.el.classList.toggle("focused", !!on);
          },

          wire() {
            if (!this.pair) return this.show(false);

            const [left, right] = this.pair;
            const g = this.el.querySelector(".lk-gutter").getBoundingClientRect();
            const l = left.getBoundingClientRect();
            const r = right.getBoundingClientRect();

            // a paragraph scrolled out of its column has no business being
            // wired to anything
            const cols = [...this.el.querySelectorAll(".lk-col")].map((c) => c.getBoundingClientRect());
            const visible = (box, col) => box.bottom > col.top + 4 && box.top < col.bottom - 4;

            if (!visible(l, cols[0]) || !visible(r, cols[1])) return this.show(false);

            const clamp = (y, col) => Math.max(col.top + 6, Math.min(y, col.bottom - 6));
            const y1 = clamp(l.top + l.height / 2, cols[0]) - g.top;
            const y2 = clamp(r.top + r.height / 2, cols[1]) - g.top;
            const w = g.width;

            // Start and finish ON the two outlined boxes, not at the edges
            // of the gutter. The columns have padding, and a line that stops
            // short of the thing it points at reads as decoration rather
            // than as a join. The svg has overflow visible, so these
            // coordinates leave the viewBox on purpose.
            const x1 = l.right - g.left;
            const x2 = r.left - g.left;
            const mid = (x1 + x2) / 2;

            this.show(true);
            this.svg.setAttribute("viewBox", `0 0 ${w} ${g.height}`);
            this.svg.dataset.kind = this.kind || "";
            // a flat S: leaves one box horizontally and arrives at the other
            // the same way, so both ends read as attached rather than aimed
            this.path.setAttribute("d", `M ${x1} ${y1} C ${mid} ${y1}, ${mid} ${y2}, ${x2} ${y2}`);
            this.dotA.setAttribute("cx", x1);
            this.dotA.setAttribute("cy", y1);
            this.dotB.setAttribute("cx", x2);
            this.dotB.setAttribute("cy", y2);
          },

          updated() {
            // a filter change re-renders the columns; whatever was open
            // should still be where it was put
            if (this.last && document.contains(this.last)) this.tandem(this.last, true);
            else this.wire();
          },

          tandem(note, quiet) {
            this.last = note;

            const side = note.dataset.side;
            const peer = note.dataset.peerRef;
            const here = document.querySelector(`#col-${side}`);
            const there = document.querySelector(`#col-${note.dataset.peer}`);
            if (!here || !there) return;

            const mine = note.closest(".lk-block");
            const theirs = peer && there.querySelector(`#blk-${note.dataset.peer}-${peer}`);

            // a third of the way down is high enough to read from and low
            // enough that the paragraph above gives it context
            const rest = (col, el) => {
              if (!el) return;
              const top = el.offsetTop - col.clientHeight * 0.3;
              col.scrollTo({top: Math.max(0, top), behavior: quiet ? "auto" : "smooth"});
            };

            rest(here, mine);
            rest(there, theirs);

            document.querySelectorAll(".lk-block.paired").forEach((b) => b.classList.remove("paired"));
            mine?.classList.add("paired");
            theirs?.classList.add("paired");

            this.pair = mine && theirs ? [mine, theirs] : null;
            this.kind = note.dataset.kind;
            // the scroll is animated, so follow it rather than drawing once
            // against positions that are about to change
            this.chase();

            if (!theirs) {
              // the far end is a spine node or a thread — a claim about the
              // whole draft, with no one paragraph to sit beside
              note.classList.add("no-peer");
              setTimeout(() => note.classList.remove("no-peer"), 1200);
            }
          },
        };
      </script>
    </Layouts.app>
    """
  end

  attr :side, :string, required: true
  attr :peer, :string, required: true
  attr :work, :map, required: true
  attr :page, :list, required: true
  attr :only, :string, default: nil
  attr :open, :integer, default: nil

  defp column(assigns) do
    ~H"""
    <div class="lk-colwrap">
      <div class="lk-colhead">
        <span class="mg-label">{if @side == "a", do: "Left", else: "Right"}</span>
        <a href={~p"/works/#{@work.slug}"} class="t">{@work.title}</a>
        <span class="n">{@work.word_count} words</span>
      </div>

      <div class="lk-col" id={"col-#{@side}"} tabindex="0">
        <%= for section <- @page do %>
          <div class="lk-sec">
            <span class="mg-label">Section {section.section.ordinal}</span>
            <h2>{section.section.title}</h2>
          </div>

          <%= for block <- section.blocks do %>
            <% notes = Enum.filter(block.notes, &shown?(&1, @only)) %>
            <div class={["lk-block", notes != [] && "linked"]} id={"blk-#{@side}-#{block.ref}"}>
              <div class="lk-prose md">
                {Reading.render_block(block.text, notes != [] && block.mark, block.ref)}
              </div>

              <div :if={notes != []} class="lk-notes">
                <button
                  :for={n <- notes}
                  class={["lk-note", n.kind, @open == n.edge_id && "open"]}
                  data-peer-ref={n.peer_ref}
                  data-kind={n.kind}
                  data-side={@side}
                  data-peer={@peer}
                  phx-click="open_edge"
                  phx-value-edge={n.edge_id}
                >
                  <span class="who">{String.replace(n.kind, "_", " ")}</span>
                  <span class="said">{n.title}</span>
                  <span class="why">{n.body}</span>
                </button>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  defp types(stats) do
    stats.by_type
    |> Enum.sort_by(fn {_t, n} -> -n end)
    |> Enum.map(fn {t, n} -> {t, "#{String.replace(t, "_", " ")} #{n}"} end)
  end

  # the conversation lives in the database, so a reload comes back to it
  defp chat_history(link) do
    case Marginalia.Repo.get_by(Marginalia.Chat.Conversation, link_id: link.id) do
      nil -> []
      convo -> LinkChat.history(convo)
    end
  end
end
