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

  alias Marginalia.{Accounts, Links, Reading, Walkthrough}
  alias Marginalia.Links.Chat, as: LinkChat

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Links.get(id) do
      nil ->
        {:ok, socket |> put_flash(:error, "No such link.") |> push_navigate(to: ~p"/works")}

      link ->
        if connected?(socket), do: Phoenix.PubSub.subscribe(Marginalia.PubSub, "link:#{link.id}")

        {:ok,
         socket
         |> assign(
           link: link,
           page_robots: "noindex, nofollow",
           chat_open: false,
           chat_thinking: false,
           chat_history: [],
           chat_cited: [],
           walk: []
         )
         |> maybe_tour()}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Switching reference is a patch to a different :id, so the link has to
    # come from the params — taking it from the assigns left the old pair
    # in place and the page showed the wrong document under the right title.
    link = swap(socket, params["id"])
    {a, b} = Links.works(link)
    {lead, other} = if params["lead"] == b.slug, do: {b, a}, else: {a, b}

    {page_a, page_b} = Links.pages(link)
    {lead_page, other_page} = if lead.id == a.id, do: {page_a, page_b}, else: {page_b, page_a}

    # the nodes the pass is relating, for the wait; skipped once it is done
    {wait_a, wait_b} = waiting_nodes(link, lead, other)

    # every other draft this one has been related to, so the reference can
    # be swapped without going back to a list
    others =
      lead.id
      |> Links.for_work()
      |> Enum.reject(&(&1.id == link.id))
      |> Enum.map(fn l -> {l, Links.other(l, lead.id)} end)

    {:noreply,
     assign(socket,
       link: link,
       # the previous leg of the tour hands over in the query string, so a
       # reader can also be sent straight into the middle of it by link
       walk: if(params["walk"] == "1", do: Walkthrough.Cases.steps(:follow), else: socket.assigns.walk),
       tour: if(params["walk"] == "1", do: nil, else: socket.assigns[:tour]),
       others: others,
       wait_a: wait_a,
       wait_b: wait_b,
       page_title: "#{lead.title} · alongside #{other.title}",
       lead: lead,
       other: other,
       lead_page: lead_page,
       other_page: other_page,
       only: params["only"],
       stats: Links.stats(link)
     )}
  end

  # --- the tour -------------------------------------------------------------

  @doc false
  # Nothing on this page announces itself: the right column dims, the wire
  # appears under the pointer, the gaps fold. Every one of those is better
  # than a label until you have never seen it before, which is everybody
  # the first time. Six sentences, once.
  def maybe_tour(socket) do
    user = socket.assigns.current_scope.user

    cond do
      Accounts.seen_tour?(user, :follow) ->
        assign(socket, tour: nil)

      # A LiveView renders twice, over HTTP and then over the socket. Marking
      # it seen on the first pass means the second pass finds it already read
      # and shows nothing at all -- the bug this page's sibling shipped with.
      connected?(socket) ->
        {:ok, user} = Accounts.mark_tour_seen(user, :follow)

        assign(socket,
          tour: Marginalia.Tour.for_view(:follow),
          current_scope: %{socket.assigns.current_scope | user: user}
        )

      true ->
        assign(socket, tour: Marginalia.Tour.for_view(:follow))
    end
  end

  def handle_event("dismiss_tour", _params, socket), do: {:noreply, assign(socket, tour: nil)}

  def handle_event("start_walk", _params, socket),
    do: {:noreply, assign(socket, tour: nil, walk: Walkthrough.Cases.steps(:follow))}

  def handle_event("end_walk", _params, socket), do: {:noreply, assign(socket, walk: [])}

  # on to the same opinion with the whole case in its margin
  def handle_event("walk_hop", %{"to" => "case_read"}, socket) do
    lead = socket.assigns.lead

    case lead.collection do
      nil -> {:noreply, assign(socket, walk: [])}
      name ->
        {:noreply,
         push_navigate(socket,
           to: ~p"/cases/#{Marginalia.Cases.slug(name)}/read/#{lead.slug}?walk=1"
         )}
    end
  end

  def handle_event("show_tour", _params, socket),
    do: {:noreply, assign(socket, tour: Marginalia.Tour.for_view(:follow))}

  # --- the chat about this pair ---------------------------------------------

  def handle_event("toggle_chat", _params, socket),
    do: {:noreply, assign(socket, chat_open: !socket.assigns.chat_open)}

  # Clicking the line between two passages puts both of them into the chat.
  # The map already names every edge; this hands over the actual prose on
  # each end, which is what a question about "this bit" needs.
  def handle_event("cite_edge", %{"edge" => id}, socket) do
    id = String.to_integer(id)
    cited = socket.assigns.chat_cited

    {:noreply,
     assign(socket,
       chat_cited: if(id in cited, do: cited, else: cited ++ [id]),
       chat_open: true
     )}
  end

  def handle_event("uncite", %{"edge" => id}, socket) do
    id = String.to_integer(id)
    {:noreply, assign(socket, chat_cited: socket.assigns.chat_cited -- [id])}
  end

  def handle_event("close_chat", _params, socket),
    do: {:noreply, assign(socket, chat_open: false)}

  def handle_event("chat_send", %{"message" => text}, socket) do
    text = String.trim(text)
    a = socket.assigns

    if text == "" or a.chat_thinking do
      {:noreply, socket}
    else
      # the turns live here and nowhere else — see Links.Chat
      history = a.chat_history ++ [%{"role" => "user", "content" => text}]
      link = a.link
      cited = a.chat_cited

      {:noreply,
       socket
       |> assign(chat_history: history, chat_thinking: true, chat_cited: [])
       |> start_async(:chat, fn -> LinkChat.ask(link, history, cited: cited) end)}
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
    {:noreply,
     assign(socket,
       chat_thinking: false,
       chat_history: socket.assigns.chat_history ++ [%{"role" => "assistant", "content" => reply}]
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
      <%!-- While the pass runs: both maps, and the pairs it is trying
            between them. The nodes are real; the arcs are not results and
            say so. --%>
      <MarginaliaWeb.LinkWaiting.waiting
        :if={@link.status != "linked"}
        a={@lead}
        b={@other}
        a_nodes={@wait_a}
        b_nodes={@wait_b}
        status={@link.status}
        error={@link.error}
      />

      <div :if={@link.status == "linked"} class="fl" id="follow" phx-hook=".Follow">
        <div class="fl-bar">
          <button class="fl-help" phx-click="show_tour" title="How this page works">?</button>
          <.link
            patch={read_path(assigns, lead: @other.slug)}
            class="fl-swap"
            title="Read the other one instead"
          >
            <span aria-hidden="true">⇄</span> swap sides
          </.link>

          <div class="fl-legend">
            <button
              :for={{id, label} <- [{"all", "Everything"} | types(@stats)]}
              class={"mg-tab" <> if((@only || "all") == id, do: " on", else: "")}
              phx-click="set_only"
              phx-value-only={id}
            >{label}</button>
          </div>

          <%!-- how much of the relationship you have actually been past --%>
          <%!-- The model's account of the relationship. It lived in the
                split view, and deleting that orphaned it — it was only
                visible on the index rows, which is not where you are when
                you want it. --%>
          <details :if={@link.summary} class="fl-sum">
            <summary>
              <span class="mg-label">why</span>
              <span class="peek">{Links.summary(@link)}</span>
              <span class="more" aria-hidden="true"></span>
            </summary>
            <p>{Links.summary(@link)}</p>
          </details>

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
            <%!-- a 2.5px line is not a thing anyone can hit. These are the
                  same two curves, invisible and fourteen pixels wide, and
                  they are what actually takes the click. --%>
            <path class="h1 hit" fill="none" />
            <path class="h2 hit" fill="none" />
          </svg>

          <div class="fl-mid">
            <%!-- The phone's answer to "what does the other document say
                  about this paragraph". A paragraph can carry five
                  connections and the sheet was showing one of them —
                  whichever happened to be first in the DOM — with no
                  sign the other four existed. So: the stack, one card
                  per connection, built by the hook because only the
                  browser knows which paragraph was tapped.

                  The strip below it is the wide-screen version and
                  stays as it was: there, the drawn line points at one
                  connection at a time, so one is the right number. --%>
            <div class="fl-sheet" hidden>
              <div class="fl-sheet-head">
                <span class="n"></span>
                <button type="button" class="shut" aria-label="Back to the reading">×</button>
              </div>
              <div class="fl-stack"></div>
            </div>

            <div class="fl-strip" hidden>
              <%!-- This head was written when the strip *was* the phone
                    UI. It is not any more — the sheet above replaced it
                    there, and `.fl-strip` is display:none under 1100px — so
                    everything here is wide-screen markup now. It used to
                    carry a × as well, left over from the phone: nothing on
                    a wide screen dismisses the strip (it follows the
                    scroll), so the button sat there doing nothing. --%>
              <div class="fl-strip-head">
                <span class="rel"></span>
                <span class="nth"></span>
              </div>
              <p class="why"></p>
              <%!-- On a phone the right-hand document has nowhere to be,
                    so the strip carries the passage itself. The hook
                    copies it out of the column, which is still in the
                    DOM — hidden, not absent. --%>
              <blockquote class="far"></blockquote>
              <%!-- Last, not in the head: you decide to ask *after* reading
                    what the connection is, and a button wedged between the
                    relation and its reason reads as part of the sentence. --%>
              <button type="button" class="ask">ask about this</button>
            </div>
            <div class="fl-idle">
              Scroll. Where this draft touches the other, it will be shown here.
            </div>
          </div>

          <div class="fl-col other" id="fl-other" tabindex="0">
            <div class="fl-colhead">
              <%!-- A draft can be related to several others, and reading it
                    against each of them in turn is the point of having
                    more than one. Swapping is here rather than back on a
                    list page. --%>
              <%= if @others == [] do %>
                <span class="mg-label">Referencing…</span>
                <a href={~p"/works/#{@other.slug}"}>{@other.title}</a>
              <% else %>
                <details class="fl-pick">
                  <summary>
                    <span class="mg-label">Referencing…</span>
                    <span class="t">{@other.title}</span>
                    <span class="n">{length(@others) + 1}</span>
                  </summary>
                  <div class="fl-pick-menu">
                    <span class="here">
                      <span class="t">{@other.title}</span>
                      <span class="mg-label">reading against this</span>
                    </span>
                    <.link
                      :for={{l, w} <- @others}
                      patch={~p"/links/#{l.id}?lead=#{@lead.slug}"}
                      class="row"
                    >
                      <span class="t">{w.title}</span>
                      <span class={["st", l.status]}>
                        {if l.status == "linked", do: "#{edge_count(l)} edges", else: l.status}
                      </span>
                    </.link>
                    <.link navigate={~p"/links"} class="row more">Relate it to another…</.link>
                  </div>
                </details>
              <% end %>
            </div>
            <.side page={@other_page} only={@only} side="other" />
          </div>
        </div>
      </div>

      <%!-- Over the page rather than beside it: the things it describes are
            the page, and a card in a corner is read after you have already
            failed to work out what the dimmed half is for. --%>
      <div :if={@tour} class="fl-tour-veil" phx-click="dismiss_tour">
        <div class="fl-tour" phx-click-away="dismiss_tour">
          <div class="fl-tour-head">
            <h2>{@tour.title}</h2>
            <button class="mg-btn sm ghost" phx-click="dismiss_tour">Got it</button>
          </div>
          <ul>
            <li :for={point <- @tour.points}>{point}</li>
          </ul>
          <p class="mg-hint">The <strong>?</strong> in the bar brings this back.</p>
        </div>
      </div>

      <MarginaliaWeb.Walk.overlay
        :if={@walk != []}
        steps={@walk}
        note="Real documents, really read: these are the Court's own files and nothing here is a fixture. The tour presses the same controls you would."
      />

      <%!-- Not while the tour card is up. The card's veil covers the whole
            viewport at a higher z-index than the bubble, so a click on the
            bubble was landing on the veil: the tour dismissed and the chat
            did not open. Twice in a row looks exactly like a broken
            button, and it was — a control you can see, cannot press, and
            get no feedback from. --%>
      <MarginaliaWeb.LinkChat.bubble
        :if={is_nil(@tour)}
        open={@chat_open}
        history={@chat_history}
        thinking={@chat_thinking}
        count={length(@chat_history)}
        cited={cited_edges(@link, @chat_cited)}
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
                    {Reading.render_block(b.text, nil, "#{@side}-#{b.ref}")}
                  </div>
                </div>
              </details>
            <% {:block, block} -> %>
              <% notes = Enum.filter(block.notes, &shown?(&1, @only)) %>
              <div class={["fl-block", notes != [] && "linked"]} id={"blk-#{@side}-#{block.ref}"}>
                <%!-- The anchor id is namespaced by side. Both columns
                      number their paragraphs from their own first one, so
                      an anchored quote at the same position in each
                      produced two elements with id "anchor-s1p1" — which
                      breaks DOM patching and means getElementById returns
                      whichever one happens to be first. --%>
                {Reading.render_block(block.text, notes != [] && block.mark, "#{@side}-#{block.ref}")}

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
                      arriving.

                      "3 links" was a dead end, though: the strip and the
                      wire only ever showed the *first* of them, so the
                      other two were counted and then unreachable. Hovering
                      the chip opens the list, and each entry goes to the
                      paragraph at its own far end. --%>
                <div :if={notes != []} class={["fl-tagwrap", tag_kind(notes)]}>
                  <span class={["fl-tag", tag_kind(notes)]}>{tag_label(notes)}</span>

                  <div class="fl-links">
                    <button
                      :for={n <- notes}
                      type="button"
                      class={["fl-jump", "k-#{n.kind}"]}
                      disabled={is_nil(n.peer_ref)}
                      data-peer-ref={n.peer_ref}
                      data-edge={n.edge_id}
                      data-kind={n.kind}
                    >
                      <span class="rel">{String.replace(n.kind, "_", " ")}</span>
                      <span class="to">{n.title}</span>
                      <span class="why">{n.body}</span>
                      <%!-- An edge whose far end is a spine node has no
                            paragraph to land on. Saying so beats a control
                            that looks live and does nothing. --%>
                      <span :if={is_nil(n.peer_ref)} class="nowhere">whole draft — no passage to jump to</span>
                    </button>
                  </div>
                </div>
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

  # ids in, something showable out
  defp cited_edges(_link, []), do: []

  defp cited_edges(link, ids) do
    link |> Links.edges() |> Enum.filter(&(&1.id in ids))
  end

  # Only while it is running: once the link is drawn the page shows the
  # real thing and these would be two unused queries on every render.
  defp waiting_nodes(%{status: "linked"}, _a, _b), do: {[], []}

  defp waiting_nodes(_link, a, b),
    do: {beats(a), beats(b)}

  defp beats(work),
    do: work.id |> Marginalia.Works.list_nodes() |> Enum.filter(&(&1.node_type == "beat"))

  # the link named in the URL, resubscribing if it is a different one
  defp swap(socket, id) do
    current = socket.assigns.link

    with false <- is_nil(id),
         {n, _} <- Integer.parse(to_string(id)),
         true <- n != current.id,
         %{} = link <- Links.get(n) do
      if connected?(socket) do
        Phoenix.PubSub.unsubscribe(Marginalia.PubSub, "link:#{current.id}")
        Phoenix.PubSub.subscribe(Marginalia.PubSub, "link:#{link.id}")
      end

      link
    else
      _ -> current
    end
  end

  defp edge_count(link), do: link |> Links.edges() |> length()
end
