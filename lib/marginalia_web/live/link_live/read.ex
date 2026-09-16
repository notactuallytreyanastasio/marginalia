defmodule MarginaliaWeb.LinkLive.Read do
  @moduledoc """
  Read one draft; the other one follows along beside it.

  The split view is driven by clicking: two documents, pair them yourself.
  This one is driven by reading. You go down the left-hand document at your
  own pace and the right-hand one is scrolled for you, always showing the
  passage that the paragraph in front of you is talking to — with the
  relation and the reason in the strip between them.

  Nothing here is a summary or a card standing in for a document. The right
  half is the other manuscript, whole, in its own scroll: you can stop
  following and read it, then carry on and it picks you up again.

  Either side can be the one you read; the pair is symmetric and the two
  directions are genuinely different experiences. The lead is in the URL so
  a particular reading can be handed to someone.
  """
  use MarginaliaWeb, :live_view

  alias Marginalia.{Links, Reading}
  alias Marginalia.Links.Chat, as: LinkChat

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Links.get(id) do
      nil ->
        {:ok, socket |> put_flash(:error, "No such link.") |> push_navigate(to: ~p"/works")}

      link ->
        if connected?(socket), do: Phoenix.PubSub.subscribe(Marginalia.PubSub, "link:#{link.id}")

        {:ok,
         assign(socket,
           link: link,
           page_robots: "noindex, nofollow",
           chat_open: false,
           chat_thinking: false,
           chat_history: chat_history(link),
           chat_convo: nil
         )}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    link = socket.assigns.link
    {a, b} = Links.works(link)
    {lead, other} = if params["lead"] == b.slug, do: {b, a}, else: {a, b}

    {page_a, page_b} = Links.pages(link)
    {lead_page, other_page} = if lead.id == a.id, do: {page_a, page_b}, else: {page_b, page_a}

    {:noreply,
     assign(socket,
       page_title: "#{lead.title} · alongside #{other.title}",
       lead: lead,
       other: other,
       lead_page: lead_page,
       other_page: other_page,
       only: params["only"],
       stats: Links.stats(link)
     )}
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
  def handle_event("relink", _params, socket) do
    Marginalia.Analysis.Linker.start(socket.assigns.link)
    {:noreply, assign(socket, link: %{socket.assigns.link | status: "linking"})}
  end

  def handle_event("set_only", %{"only" => only}, socket) do
    only = if only in ["", "all"], do: nil, else: only
    {:noreply, push_patch(socket, to: read_path(socket.assigns, only: only))}
  end

  defp read_path(a, overrides) do
    only = Keyword.get(overrides, :only, a.only)
    lead = Keyword.get(overrides, :lead, a.lead.slug)
    params = if only, do: %{"lead" => lead, "only" => only}, else: %{"lead" => lead}

    ~p"/links/#{a.link.id}/read?#{params}"
  end

  defp shown?(_note, nil), do: true
  defp shown?(note, only), do: note.kind == only

  @impl true
  def handle_info({:link, _}, socket) do
    link = Links.get(socket.assigns.link.id)
    params = %{"lead" => socket.assigns.lead.slug, "only" => socket.assigns.only}
    {:noreply, socket |> assign(link: link) |> then(&reload(&1, params))}
  end

  defp reload(socket, params) do
    {:noreply, socket} = handle_params(params, "", socket)
    socket
  end

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
          <strong>{@lead.title}</strong> and <strong>{@other.title}</strong>. It is reading both
          graphs — every beat, the spine, the threads — and drawing the edges between them.
          A minute or two. This page fills in on its own.
        </p>
      </div>

      <div :if={@link.status == "failed"} class="lk-wait">
        <h2>That did not go through</h2>
        <p>{@link.error}</p>
        <button class="mg-btn sm" phx-click="relink">Try again</button>
      </div>

      <div :if={@link.status == "linked"} class="fl" id="follow" phx-hook=".Follow">
        <div class="fl-bar">
          <.link
            patch={read_path(assigns, lead: @other.slug)}
            class="fl-swap"
            title="Read the other one instead"
          >
            <span aria-hidden="true">⇄</span> swap sides
          </.link>

          <div class="fl-tabs">
            <.link navigate={~p"/links/#{@link.id}"} class="mg-tab">Split</.link>
            <span class="mg-tab on">Follow</span>
          </div>

          <div class="fl-legend">
            <button
              :for={{id, label} <- [{"all", "Everything"} | types(@stats)]}
              class={"mg-tab" <> if((@only || "all") == id, do: " on", else: "")}
              phx-click="set_only"
              phx-value-only={id}
            >{label}</button>
          </div>

          <%!-- how much of the relationship you have actually been past --%>
          <span class="fl-count"><b>0</b> / {@stats.edges} addressed</span>
        </div>

        <div class="fl-split">
          <div class="fl-col lead" id="fl-lead" tabindex="0">
            <%!-- which column is which, kept in view: three screens down,
                  "the left one" is not something anyone is still tracking --%>
            <div class="fl-colhead">
              <span class="mg-label">Reading…</span>
              <a href={~p"/works/#{@lead.slug}"}>{@lead.title}</a>
            </div>
            <.side page={@lead_page} only={@only} side="lead" />
          </div>

          <%!-- the reason lives between the two documents, which is where it
                is about: it belongs to neither and points at both --%>
          <%!-- The line is drawn across the whole split, not just the
                gutter, so it can start and finish on the two passages
                themselves. It runs THROUGH the reason card rather than past
                it: left passage → why → right passage is the actual shape
                of the claim. --%>
          <svg class="fl-wire" hidden>
            <path class="w1" fill="none" />
            <path class="w2" fill="none" />
            <circle class="d1" r="4" />
            <circle class="d2" r="4" />
          </svg>

          <div class="fl-mid">
            <div class="fl-strip" hidden>
              <span class="rel"></span>
              <p class="why"></p>
              <span class="nth"></span>
            </div>
            <div class="fl-idle">
              Scroll. Where this draft touches the other, it will be shown here.
            </div>
          </div>

          <div class="fl-col other" id="fl-other" tabindex="0">
            <div class="fl-colhead">
              <span class="mg-label">Referencing…</span>
              <a href={~p"/works/#{@other.slug}"}>{@other.title}</a>
            </div>
            <.side page={@other_page} only={@only} side="other" />
          </div>
        </div>
      </div>

      <MarginaliaWeb.LinkChat.bubble
        open={@chat_open}
        history={@chat_history}
        thinking={@chat_thinking}
        count={length(@chat_history)}
      />

      <script :type={Phoenix.LiveView.ColocatedHook} name=".Follow">
        // The left column is read; the right one is driven.
        //
        // A focus line a third of the way down the left column decides what
        // you are "on". Whichever linked paragraph last crossed it is the
        // current one, and the right column is scrolled to put its
        // counterpart at the same height. Reading is the input; nothing has
        // to be clicked.
        export default {
          mounted() {
            this.lead = this.el.querySelector("#fl-lead");
            this.other = this.el.querySelector("#fl-other");
            this.strip = this.el.querySelector(".fl-strip");
            this.svg = this.el.querySelector(".fl-wire");
            this.split = this.el.querySelector(".fl-split");
            this.idle = this.el.querySelector(".fl-idle");
            this.count = this.el.querySelector(".fl-count b");
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

            this.follow();
          },

          updated() { this.seen.clear(); this.current = null; this.follow(); },

          destroyed() {
            this.lead.removeEventListener("scroll", this.onScroll);
            this.el.removeEventListener("wheel", this.onWheel);
            cancelAnimationFrame(this.frame);
            window.removeEventListener("resize", this.onScroll);
          },

          release() { this.free = true; },

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
            const block = this.currentBlock();
            if (!block) return this.blank();

            if (block !== this.current) {
              this.current = block;
              this.free = false;
              this.mark(block);
            }

            if (!this.free) this.align(block);
          },

          mark(block) {
            const note = block.querySelector("[data-peer-ref]");
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
            this.svg.dataset.kind = note.dataset.kind;
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
            this.svg.querySelector(".w1").setAttribute(
              "d", `M ${x1} ${y1} C ${(x1 + x2) / 2} ${y1}, ${(x1 + x2) / 2} ${ym}, ${x2} ${ym}`);
            this.svg.querySelector(".w2").setAttribute(
              "d", `M ${x3} ${ym} C ${(x3 + x4) / 2} ${ym}, ${(x3 + x4) / 2} ${y4}, ${x4} ${y4}`);
            this.svg.querySelector(".d1").setAttribute("cx", x1);
            this.svg.querySelector(".d1").setAttribute("cy", y1);
            this.svg.querySelector(".d2").setAttribute("cx", x4);
            this.svg.querySelector(".d2").setAttribute("cy", y4);
          },

          // put the cited passage at the same height as the one being read
          align(block) {
            const note = block.querySelector("[data-peer-ref]");
            const peer = note && this.other.querySelector(`#blk-other-${note.dataset.peerRef}`);
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
        };
      </script>
    </Layouts.app>
    """
  end

  attr :page, :list, required: true
  attr :only, :string, default: nil
  attr :side, :string, required: true

  defp side(assigns) do
    ~H"""
    <div class="fl-inner">
      <%= for section <- @page do %>
        <div class="fl-sec">
          <span class="mg-label">Section {section.section.ordinal}</span>
          <h2>{section.section.title}</h2>
        </div>

        <%= for run <- condense(section.blocks, @only) do %>
          <%= case run do %>
            <% {:gap, blocks} -> %>
              <%!-- The stretches where the two documents have nothing to say
                    to each other are folded away. This view is for an
                    editorial pass over the relationship, and prose with
                    nothing beside it is the part you are not here for —
                    still one click from being read, never deleted. --%>
              <details class="fl-gap">
                <summary>
                  <span class="n">{length(blocks)} paragraphs</span>
                  <span class="w">{words(blocks)} words</span>
                </summary>
                <div class="fl-gap-body">
                  <div :for={b <- blocks} class="fl-block quiet" id={"blk-#{@side}-#{b.ref}"}>
                    {Reading.render_block(b.text, nil, b.ref)}
                  </div>
                </div>
              </details>
            <% {:block, block} -> %>
              <% notes = Enum.filter(block.notes, &shown?(&1, @only)) %>
              <div class={["fl-block", notes != [] && "linked"]} id={"blk-#{@side}-#{block.ref}"}>
                {Reading.render_block(block.text, notes != [] && block.mark, block.ref)}

                <%!-- the relation is carried on the paragraph as data; the strip
                  between the columns is what actually shows it --%>
                <span
                  :for={n <- notes}
                  hidden
                  data-peer-ref={n.peer_ref}
                  data-kind={n.kind}
                  data-why={n.body}
                  data-edge={n.edge_id}
                  data-src={n.title}
                ></span>

                <%!-- One chip, not one word per edge. A hub paragraph can
                      have a dozen edges pointing at it, and a dozen labels
                      in a row overflowed the column and sat behind the
                      prose. The count is the more useful fact anyway: it
                      says this passage is where the other document keeps
                      arriving. --%>
                <span :if={notes != []} class={["fl-tag", tag_kind(notes)]}>{tag_label(notes)}</span>
              </div>
          <% end %>
        <% end %>
      <% end %>
    </div>
    """
  end

  # the relation, when there is only one; the count when there are several
  defp tag_label([n]), do: String.replace(n.kind, "_", " ")
  defp tag_label(notes), do: "#{length(notes)} links"

  # colour by the relation if they agree, neutral if they do not
  defp tag_kind(notes) do
    case notes |> Enum.map(& &1.kind) |> Enum.uniq() do
      [one] -> one
      _ -> "mixed"
    end
  end

  # Blocks that carry a link, plus one paragraph either side so the linked
  # one is not read out of context, and everything else gathered into gaps.
  #
  # A run of one is left alone: a control that hides a single paragraph
  # costs more attention than the paragraph did.
  defp condense(blocks, only) do
    linked =
      blocks
      |> Enum.with_index()
      |> Enum.filter(fn {b, _} -> Enum.any?(b.notes, &shown?(&1, only)) end)
      |> Enum.map(fn {_, i} -> i end)
      |> MapSet.new()

    keep =
      Enum.reduce(linked, MapSet.new(), fn i, acc ->
        acc |> MapSet.put(i - 1) |> MapSet.put(i) |> MapSet.put(i + 1)
      end)

    blocks
    |> Enum.with_index()
    |> Enum.chunk_by(fn {_, i} -> MapSet.member?(keep, i) end)
    |> Enum.flat_map(fn chunk ->
      {_, i} = hd(chunk)

      cond do
        MapSet.member?(keep, i) -> Enum.map(chunk, fn {b, _} -> {:block, b} end)
        length(chunk) == 1 -> Enum.map(chunk, fn {b, _} -> {:block, b} end)
        true -> [{:gap, Enum.map(chunk, fn {b, _} -> b end)}]
      end
    end)
  end

  defp words(blocks),
    do: blocks |> Enum.map(&(&1.text |> String.split() |> length())) |> Enum.sum()

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
