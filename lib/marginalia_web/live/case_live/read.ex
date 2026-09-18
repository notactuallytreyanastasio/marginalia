defmodule MarginaliaWeb.CaseLive.Read do
  @moduledoc """
  A case read three ways at once.

  `/links/:id/read` is pairwise by construction: one document on the left,
  one in the margin, and a scroll that drives the second from the first. A
  case is not pairwise. The opinion is answering the dissent *and* the
  advocate who was asked about exactly that at the lectern, and the moments
  worth having are the ones where both land on the same paragraph — which
  is precisely what reading the pair twice, separately, hides.

  So the margin here is merged: every link in the collection that touches
  the document you are reading, in one column, each note stamped with where
  it came from. A paragraph with the dissent and two advocates on it shows
  all three, in reading order.

  ## Why this is a grid and not a scroll mechanic

  The follow view aligns two columns by driving one from the other, which
  took three attempts to get right and only works for two. Three sources
  cannot be scroll-synced to one lead at all — they would fight. Here each
  paragraph and its notes are one row of a CSS grid, so they are level
  because the layout says so, with no measurement, no hook, and nothing to
  drift. The cost is whitespace next to a short paragraph carrying a tall
  stack of notes, which is an honest picture of that paragraph.
  """
  use MarginaliaWeb, :live_view

  alias Marginalia.{Cases, Reading, Walkthrough}
  alias Marginalia.Cases.Chat, as: CaseChat

  @impl true
  def mount(%{"slug" => slug} = params, _session, socket) do
    case Cases.published() |> Enum.find(&(&1.slug == slug)) do
      nil ->
        {:ok, socket |> put_flash(:error, "No such case.") |> push_navigate(to: ~p"/cases")}

      c ->
        {:ok,
         socket
         |> assign(
           case: c,
           only: nil,
           source: nil,
           peek: nil,
           walk: [],
           chat_open: false,
           chat_thinking: false,
           chat_history: [],
           chat_cited: []
         )
         |> load(params["lead"])}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket = load(socket, params["lead"])

    # the last leg of the tour arrives here from the pairwise reading
    {:noreply,
     if params["walk"] == "1" do
       assign(socket, walk: Walkthrough.Cases.steps(:case_read))
     else
       socket
     end}
  end

  def handle_event("start_walk", _params, socket),
    do: {:noreply, assign(socket, walk: Walkthrough.Cases.steps(:case_read))}

  def handle_event("end_walk", _params, socket), do: {:noreply, assign(socket, walk: [])}

  def handle_event("walk_hop", _params, socket), do: {:noreply, assign(socket, walk: [])}

  # Filters are patch-free: they change what is shown, not what is loaded,
  # and putting them in the URL would make every chip a history entry.
  @impl true
  def handle_event("only", %{"k" => k}, socket),
    do: {:noreply, assign(socket, only: toggle(socket.assigns.only, k))}

  def handle_event("source", %{"w" => w}, socket),
    do: {:noreply, assign(socket, source: toggle(socket.assigns.source, w))}

  def handle_event("clear", _params, socket),
    do: {:noreply, assign(socket, only: nil, source: nil, peek: nil)}

  # On a phone the margin is a rail of marks rather than a column of
  # cards; tapping one brings its paragraph's notes up from the bottom.
  # --- the chat about this case --------------------------------------------

  def handle_event("toggle_chat", _params, socket),
    do: {:noreply, assign(socket, chat_open: !socket.assigns.chat_open)}

  # A note is a connection between this paragraph and a passage in
  # another document; clicking it hands both of them over.
  def handle_event("cite_edge", %{"edge" => id}, socket) do
    id = String.to_integer(id)
    cited = socket.assigns.chat_cited

    {:noreply,
     assign(socket,
       chat_cited: if(id in cited, do: cited, else: cited ++ [id]),
       chat_open: true,
       peek: nil
     )}
  end

  def handle_event("uncite", %{"edge" => id}, socket) do
    id = String.to_integer(id)
    {:noreply, assign(socket, chat_cited: socket.assigns.chat_cited -- [id])}
  end

  def handle_event("chat_send", %{"message" => text}, socket) do
    text = String.trim(text)
    a = socket.assigns

    if text == "" or a.chat_thinking or is_nil(a.reading) do
      {:noreply, socket}
    else
      history = a.chat_history ++ [%{"role" => "user", "content" => text}]
      reading = a.reading
      cited = a.chat_cited

      {:noreply,
       socket
       |> assign(chat_history: history, chat_thinking: true, chat_cited: [])
       |> start_async(:chat, fn -> CaseChat.ask(reading, history, cited: cited) end)}
    end
  end

  def handle_event("peek", %{"ref" => ref}, socket),
    do: {:noreply, assign(socket, peek: ref)}

  def handle_event("unpeek", _params, socket), do: {:noreply, assign(socket, peek: nil)}

  @impl true
  def handle_async(:chat, {:ok, {:ok, text}}, socket) do
    {:noreply,
     assign(socket,
       chat_thinking: false,
       chat_history: socket.assigns.chat_history ++ [%{"role" => "assistant", "content" => text}]
     )}
  end

  def handle_async(:chat, {:ok, {:error, reason}}, socket),
    do: {:noreply, socket |> assign(chat_thinking: false) |> chat_failed(reason)}

  def handle_async(:chat, {:exit, reason}, socket),
    do: {:noreply, socket |> assign(chat_thinking: false) |> chat_failed(reason)}

  defp chat_failed(socket, reason),
    do: put_flash(socket, :error, "That did not go through: #{inspect(reason)}")

  defp toggle(current, value), do: if(current == value, do: nil, else: value)

  defp load(socket, lead_slug) do
    c = socket.assigns.case
    lead = Enum.find(c.works, &(&1.slug == lead_slug)) || Cases.default_lead(c)

    case lead && Cases.reading(c, lead.id) do
      nil ->
        assign(socket, reading: nil, page_title: c.name)

      r ->
        assign(socket,
          reading: r,
          page_url: url(~p"/cases/#{c.slug}/read/#{r.lead.slug}"),
          page_image: ~p"/images/og-cases.png",
          page_title: "#{r.lead.title} · read against the case",
          page_description:
            "#{r.lead.title}, read with #{length(r.sources)} other documents from #{c.name} in the margin."
        )
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} bleed>
      <MarginaliaWeb.Walk.overlay
        :if={@walk != []}
        steps={@walk}
        note="Real documents, really read: these are the Court's own files and nothing here is a fixture. The tour presses the same controls you would."
      />

      <MarginaliaWeb.LinkChat.bubble
        :if={@reading}
        open={@chat_open}
        history={@chat_history}
        thinking={@chat_thinking}
        count={length(@chat_history)}
        cited={cited_edges(@reading, @chat_cited)}
        title="About this case"
        label="Talk about how these documents sit together"
        hint={
          "This one holds every document in the case and every connection between the one " <>
            "you are reading and the rest. Ask what the dissent already answered, what the " <>
            "lectern settled, or which of the disagreements is real. It writes for none of them."
        }
        placeholder="How do these sit together?"
        openers={[
          "What did the dissent already answer?",
          "What did the advocates concede that the opinion then relied on?",
          "Where do these documents actually collide?"
        ]}
      />

      <%!-- What the rail opens. A sheet rather than a dialog: it comes
            from the edge the thumb is at, and the paragraph it belongs to
            stays visible above it. --%>
      <div :if={@peek && peeked(@reading, @peek) != []} class="cr-sheet-veil" phx-click="unpeek">
        <div class="cr-sheet" phx-click-away="unpeek">
          <div class="cr-sheet-head">
            <span class="mg-label">on this paragraph</span>
            <button phx-click="unpeek" aria-label="close">×</button>
          </div>
          <.note
            :for={n <- peeked(@reading, @peek)}
            note={n}
            rank={rank_id(@reading, n)}
            lead={@reading.lead}
            elsewhere={elsewhere(@reading, n)}
          />
        </div>
      </div>

      <div :if={is_nil(@reading)} class="cr-empty">
        <p>Nothing in <b>{@case.name}</b> has been read yet.</p>
        <.link navigate={~p"/cases/#{@case.slug}"} class="mg-btn">Back to the case</.link>
      </div>

      <div :if={@reading} class="cr">
        <div class="cr-bar">
         <div class="cr-bar-in">
          <div class="cr-who">
            <span class="mg-label">Reading…</span>
            <details class="cr-pick">
              <summary>
                <span class="t">{@reading.lead.title}</span>
                <span class="n">{length(@case.works)}</span>
              </summary>
              <div class="cr-pick-menu">
                <.link
                  :for={w <- @case.works}
                  patch={~p"/cases/#{@case.slug}/read/#{w.slug}"}
                  class={["row", w.id == @reading.lead.id && "here"]}
                >
                  <span class="t">{w.title}</span>
                  <span class="r">{w.collection_role}</span>
                </.link>
              </div>
            </details>
          </div>

          <%!-- Which documents are speaking, and how loudly. The count is
                the useful half: it says which of the other documents this
                one is actually arguing with. --%>
          <div class="cr-srcs">
            <span class="mg-label">Against…</span>
            <button
              :for={{w, n} <- source_counts(@reading)}
              class={[
                "cr-chip",
                "s#{rank(w)}",
                w.collection != @case.name && "far",
                @source == to_string(w.id) && "on"
              ]}
              phx-click="source"
              phx-value-w={w.id}
              title={w.title}
            >
              <span class="t">{chip(w, @case.name)}</span>
              <span class="n">{n}</span>
            </button>
          </div>

          <div class="cr-kinds">
            <button
              :for={{k, n} <- kind_counts(@reading)}
              class={["cr-chip", "k-#{k}", @only == k && "on"]}
              phx-click="only"
              phx-value-k={k}
            >
              <span class="t">{String.replace(k, "_", " ")}</span>
              <span class="n">{n}</span>
            </button>
            <button :if={@only || @source} class="cr-clear" phx-click="clear">clear</button>
          </div>
         </div>
        </div>

        <div class="cr-grid">
          <%= for section <- @reading.page do %>
            <div class="cr-sechead">
              <span class="mg-label">Section {section.section.ordinal}</span>
              <h2>{section.section.title}</h2>
            </div>

            <%= for run <- condense(section.blocks, @only, @source) do %>
              <%= case run do %>
                <% {:gap, blocks} -> %>
                  <%!-- Prose nothing else in the case touches. Folded, never
                        dropped: this is a reading view, and a reader must be
                        able to satisfy themselves that the quiet stretches
                        really are quiet. --%>
                  <details class="cr-gap">
                    <summary>
                      <span class="n">{length(blocks)} paragraphs</span>
                      <span class="w">{words(blocks)} words</span>
                      <span class="s">nothing else in the case touches this</span>
                    </summary>
                    <div :for={b <- blocks} class="cr-quiet">
                      {Reading.render_block(b.text, nil, b.ref)}
                    </div>
                  </details>
                <% {:block, block, notes} -> %>
                  <div class={["cr-text", notes != [] && "linked"]} id={"b-#{block.ref}"}>
                    {Reading.render_block(block.text, notes != [] && block.mark, block.ref)}
                  </div>
                  <% {shown, rest} = cap(notes) %>
                  <div class={["cr-notes", notes == [] && "bare"]}>
                    <.note
                      :for={n <- shown}
                      note={n}
                      rank={rank_id(@reading, n)}
                      lead={@reading.lead}
                      elsewhere={elsewhere(@reading, n)}
                    />

                    <%!-- A hub paragraph can draw eighteen notes, which makes
                          a grid row two thousand pixels tall beside four
                          lines of prose. The first few are spread across the
                          documents rather than taken in order, so a cap never
                          silently hides a whole source. --%>
                    <%!-- Phone only: the notes collapse to one mark per
                          relation, still beside the paragraph, and the
                          reading itself gets the full width. --%>
                    <button
                      :if={notes != []}
                      class="cr-rail"
                      phx-click="peek"
                      phx-value-ref={block.ref}
                      aria-label={"#{length(notes)} connections on this paragraph"}
                    >
                      <span :for={n <- Enum.take(notes, 4)} class={["tick", "k-#{n.kind}"]}></span>
                      <span class="c">{length(notes)}</span>
                    </button>

                    <details :if={rest != []} class="cr-more">
                      <summary>{length(rest)} more on this paragraph</summary>
                      <.note
                        :for={n <- rest}
                        note={n}
                        rank={rank_id(@reading, n)}
                        lead={@reading.lead}
                        elsewhere={elsewhere(@reading, n)}
                      />
                    </details>
                  </div>
              <% end %>
            <% end %>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :note, :map, required: true
  attr :rank, :integer, required: true
  attr :lead, :map, required: true
  attr :elsewhere, :string, default: nil

  defp note(assigns) do
    ~H"""
    <article class={["cr-note", "s#{@rank}", @elsewhere && "far"]}>
      <header>
        <span class="src">{short_title(@note.from_title)}</span>
        <span class={["rel", "k-#{@note.kind}"]}>{String.replace(@note.kind, "_", " ")}</span>
      </header>
      <%!-- A note from another case has to say so, or it reads as this
            case contradicting itself. --%>
      <p :if={@elsewhere} class="from">{@elsewhere}</p>
      <p class="why">{@note.body}</p>
      <%!-- The far end, in its own words. A note that says "this answers §4
            of the dissent" is a reference; one carrying the sentence is
            something you can actually read without leaving. --%>
      <blockquote :if={@note.far_quote}>{@note.far_quote}</blockquote>
      <footer>
        <span :if={@note.far_section}>§{@note.far_section}</span>
        <button phx-click="cite_edge" phx-value-edge={@note.edge_id} class="ask">
          talk about this
        </button>
        <.link navigate={~p"/links/#{@note.link_id}?lead=#{@lead.slug}"}>read the pair →</.link>
      </footer>
    </article>
    """
  end

  # How many notes a paragraph shows before the rest are folded.
  @cap 5

  @doc false
  # Round-robin across the documents, so the visible few are never all from
  # one of them. Taking the first five in source order would show five notes
  # from the dissent and none from either advocate on exactly the paragraphs
  # where all three have something to say -- which is the case this whole
  # page exists for.
  def cap(notes) when length(notes) <= @cap, do: {notes, []}

  def cap(notes) do
    ordered =
      notes
      |> Enum.group_by(& &1.from_work)
      |> Enum.sort_by(fn {work, _} -> Enum.find_index(Enum.map(notes, & &1.from_work), &(&1 == work)) end)
      |> Enum.map(fn {_work, ns} -> ns end)
      |> interleave()

    Enum.split(ordered, @cap)
  end

  defp interleave([]), do: []

  defp interleave(lists) do
    {heads, tails} =
      lists
      |> Enum.reduce({[], []}, fn
        [], acc -> acc
        [h | t], {heads, tails} -> {[h | heads], [t | tails]}
      end)

    Enum.reverse(heads) ++ interleave(Enum.reverse(tails) |> Enum.reject(&(&1 == [])))
  end

  # --- what the chips count -------------------------------------------------

  defp source_counts(r) do
    by_work = Enum.frequencies_by(r.notes, & &1.from_work)

    r.sources
    |> Enum.map(fn %{work: w} -> {w, Map.get(by_work, w.id, 0)} end)
    |> Enum.reject(fn {_w, n} -> n == 0 end)
  end

  defp kind_counts(r) do
    r.notes |> Enum.frequencies_by(& &1.kind) |> Enum.sort_by(fn {_k, n} -> -n end)
  end

  # A source's colour is its position in the case, not its id, so the dissent
  # is the same colour on every page.
  defp rank(work) do
    case Enum.find_index(Cases.roles(), &(&1 == work.collection_role)) do
      nil -> 9
      i -> i
    end
  end

  # the cited connections, as the chat panel wants them
  defp cited_edges(nil, _ids), do: []
  defp cited_edges(_reading, []), do: []

  defp cited_edges(reading, ids) do
    reading |> CaseChat.edges() |> Enum.map(&elem(&1, 1)) |> Enum.filter(&(&1.id in ids))
  end

  # the notes on one paragraph, found by the ref the rail carries
  defp peeked(nil, _ref), do: []

  defp peeked(reading, ref) do
    Enum.find_value(reading.page, [], fn section ->
      Enum.find_value(section.blocks, fn b ->
        if to_string(b.ref) == to_string(ref), do: b.notes
      end)
    end)
  end

  # the case a note came from, when that is not the one being read
  defp elsewhere(r, note) do
    Enum.find_value(r.sources, fn s -> s.elsewhere && s.work.id == note.from_work && s.elsewhere end)
  end

  # inside the case, the document's own name is enough; from outside, the
  # case is the thing worth saying
  defp chip(work, name) do
    if work.collection == name, do: short(work), else: work.collection
  end

  defp rank_id(r, note) do
    case Enum.find(r.sources, &(&1.work.id == note.from_work)) do
      nil -> 9
      %{work: w} -> rank(w)
    end
  end

  # "Trump v. Slaughter — Argument: Amit Agarwal" is the title; in a chip
  # the case name is the part the reader already knows.
  defp short(work), do: short_title(work.title)

  defp short_title(nil), do: ""

  defp short_title(title) do
    case String.split(title, " — ", parts: 2) do
      [_case, rest] -> rest
      [whole] -> whole
    end
  end

  # --- which paragraphs earn a row -----------------------------------------

  defp shown?(note, only, source) do
    (is_nil(only) or note.kind == only) and
      (is_nil(source) or to_string(note.from_work) == source)
  end

  # Blocks carrying a visible note, plus one either side for context, kept as
  # rows; everything else gathered into a foldable gap. A run of one is left
  # alone — a control that hides a single paragraph costs more than it saves.
  defp condense(blocks, only, source) do
    kept =
      blocks
      |> Enum.with_index()
      |> Enum.filter(fn {b, _i} -> Enum.any?(b.notes, &shown?(&1, only, source)) end)
      |> Enum.flat_map(fn {_b, i} -> [i - 1, i, i + 1] end)
      |> MapSet.new()

    blocks
    |> Enum.with_index()
    |> Enum.chunk_by(fn {_b, i} -> MapSet.member?(kept, i) end)
    |> Enum.flat_map(fn chunk ->
      {_b, i} = hd(chunk)

      if MapSet.member?(kept, i) or length(chunk) == 1 do
        Enum.map(chunk, fn {b, _i} ->
          {:block, b, Enum.filter(b.notes, &shown?(&1, only, source))}
        end)
      else
        [{:gap, Enum.map(chunk, fn {b, _i} -> b end)}]
      end
    end)
  end

  defp words(blocks) do
    blocks |> Enum.map(&length(String.split(&1.text, ~r/\s+/, trim: true))) |> Enum.sum()
  end
end
