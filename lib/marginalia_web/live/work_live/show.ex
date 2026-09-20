defmodule MarginaliaWeb.WorkLive.Show do
  @moduledoc """
  The work page: the confirm gate, then the read filling in live, then
  the chat beside it.

  URL is the source of truth for which tab is open and whether the chat is
  showing, so a view survives a reload and can be shared — the same
  `push_patch(replace: true)` arrangement as the explorer this came from.
  """
  use MarginaliaWeb, :live_view

  alias Marginalia.{Works, Analysis, Chat, Accounts, Graph, Walkthrough, Links}
  alias Marginalia.Analysis.DecisionGraph
  alias Marginalia.Chat.Editor

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    # the slug is the permission to read: anyone holding the link gets the
    # page, and `owner?` decides what they can do once they are on it
    case Works.get_by_slug(id) do
      nil ->
        {:ok, socket |> put_flash(:error, "No such draft.") |> push_navigate(to: ~p"/works")}

      work ->
        if connected?(socket),
          do: Phoenix.PubSub.subscribe(Marginalia.PubSub, Analysis.topic(work.id))

        {:ok, convo} = Chat.get_or_create_conversation(work.id)

        {:ok,
         socket
         |> assign(
           page_title: work.title,
           # a draft is private by link: the URL is the permission, and an
           # indexed draft is one a search for a sentence of it would hand to
           # anybody
           page_robots: "noindex, nofollow",
           work: work,
           conversation: convo,
           history: Chat.history(convo.id),
           view: :read,
           chat_open: false,
           draft: "",
           loading: false,
           graph_json: nil,
           graph_stats: nil,
           events: [],
           event_stats: nil,
           page: nil,
           # everything, on arrival. Opening on the beats alone hid the
           # cross-section work behind a filter most people never touched,
           # and the connections and tensions are the part of the reading
           # that no one else was going to do for them.
           # nil is the canonical "no filter" — see set_only
           only: nil,
           focus: nil,
           quota: Chat.remaining(socket.assigns.current_scope.user),
           threads_list: Chat.conversation_summaries(work.id),
           cited: [],
           block_threads: Chat.threads_by_block(work.id),
           open_thread: nil,
           rewrite: nil,
           rewriting: false,
           revision_count: Works.revision_count(work.id),
           diff_rows: [],
           summarising: MapSet.new(),
           doc_running: false,
           # the read view, with what changed beside the prose instead of the
           # notes. Off until there is something to show.
           changes_on: false,
           # what the last accepted change replaced, so the paragraph it landed
           # in can show the before against the after where it happened
           applied: nil,
           document: Marginalia.Document.get(work.id),
           diff_stat: nil,
           revisions: [],
           # the writer's optional note on the rewrite, kept so the box still
           # holds what they typed when the candidates come back
           steer: nil,
           rewrite_span: nil,
           rewrite_ref: nil,
           editing: nil,
           edit_text: nil,
           tour: nil,
           # the walkthrough: a list of steps for the client, and the flag
           # that makes every write and every model call a no-op while it runs
           walk: [],
           demo: false,
           # relating this draft to another one
           links: Links.for_work(work.id),
           linking?: false,
           preview: nil,
           thread_history: [],
           thread_loading: false,
           stages: infer_stages(work),
           started_at: if(work.status == "reading", do: DateTime.to_unix(work.inserted_at)),
           passes: Analysis.passes() ++ DecisionGraph.passes() ++ Marginalia.Rewrite.passes(),
           graph_building: false,
           mode: convo.mode,
           modes: Editor.modes(),
           provider: Accounts.provider_for(socket.assigns.current_scope.user),
           admin?: socket.assigns.current_scope.user.is_admin,
           owner?: Accounts.owner?(socket.assigns.current_scope.user),
           mine?: Works.owner?(work, socket.assigns.current_scope.user),
           backends: Marginalia.LLM.choices(),
           llm_ready:
             Marginalia.LLM.configured?(Accounts.provider_for(socket.assigns.current_scope.user))
         )
         |> load_map()}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(view: to_view(params["view"]), chat_open: params["chat"] == "1")
     |> load_for_view()
     |> maybe_tour()}
  end

  # The graph export and the trace are both expensive enough not to build on
  # every mount, so they load when their tab is the one being looked at. This
  # runs on patch *and* on a direct link to `?view=graph`, which is the bit
  # that was missing: arriving at a tab by URL has to fill it in too.
  # hiding a tab is not the same as closing a door: these are reachable by
  # URL, so the view itself falls back to the page

  # the tour for a tab, the first time that tab is opened
  defp maybe_tour(socket) do
    user = socket.assigns.current_scope.user
    view = socket.assigns.view

    cond do
      Accounts.seen_tour?(user, view) ->
        assign(socket, tour: nil)

      tour = Marginalia.Tour.for_view(view) ->
        # Marked seen on sight rather than on dismissal: a tour that comes
        # back because you navigated away mid-read feels broken, and Help is
        # there for anyone who wants it again.
        #
        # Only once connected, though. A LiveView renders twice — once over
        # HTTP, once over the socket — and marking it on the first pass meant
        # the second pass saw it as already read and showed nothing at all.
        if connected?(socket) do
          {:ok, user} = Accounts.mark_tour_seen(user, view)
          scope = %{socket.assigns.current_scope | user: user}
          assign(socket, tour: tour, current_scope: scope)
        else
          assign(socket, tour: tour)
        end

      true ->
        assign(socket, tour: nil)
    end
  end

  defp load_for_view(%{assigns: %{view: v, owner?: false}} = socket) when v in [:trace, :prompts],
    do: socket |> assign(view: :read) |> load_page()

  defp load_for_view(%{assigns: %{view: :read}} = socket), do: load_page(socket)

  defp load_for_view(%{assigns: %{view: :graph, graph_json: nil}} = socket),
    do: load_graph(socket)

  defp load_for_view(%{assigns: %{view: :trace}} = socket), do: load_trace(socket)

  defp load_for_view(%{assigns: %{view: :changes}} = socket), do: load_changes(socket)
  defp load_for_view(socket), do: socket

  defp to_view("read"), do: :read
  defp to_view("spine"), do: :spine
  defp to_view("threads"), do: :threads
  defp to_view("graph"), do: :graph
  defp to_view("changes"), do: :changes
  defp to_view("trace"), do: :trace
  defp to_view("prompts"), do: :prompts
  # the page itself is what anyone should land on, not a report about it
  defp to_view(_), do: :read

  defp path(socket) do
    w = socket.assigns.work
    params = %{"view" => Atom.to_string(socket.assigns.view)}
    params = if socket.assigns.chat_open, do: Map.put(params, "chat", "1"), else: params
    ~p"/works/#{w.slug}?#{params}"
  end

  # Built on the way into the tab rather than on mount: a draft with no edits
  # has nothing to show, and one with many is an LCS over every paragraph.
  defp load_changes(socket) do
    work = socket.assigns.work
    rows = Marginalia.Diff.rows(Works.baseline(work), work.body)

    assign(socket,
      diff_rows: rows,
      diff_stat: Marginalia.Diff.stat(rows),
      revisions: Enum.reverse(Works.revisions(work.id))
    )
  end

  defp load_graph(socket) do
    w = socket.assigns.work
    assign(socket, graph_json: Jason.encode!(Graph.export(w)), graph_stats: Graph.stats(w))
  end

  defp switch_to(socket, convo) do
    assign(socket,
      conversation: convo,
      history: Chat.history(convo.id),
      mode: convo.mode,
      focus: nil,
      cited: [],
      loading: false,
      chat_open: true,
      threads_list: Chat.conversation_summaries(socket.assigns.work.id)
    )
  end

  defp load_page(socket) do
    assign(socket, page: Marginalia.Reading.page(socket.assigns.work, only: socket.assigns.only))
  end

  defp load_trace(socket) do
    w = socket.assigns.work
    assign(socket, events: Works.list_events(w.id), event_stats: Works.event_stats(w.id))
  end

  # Everything a read broadcasts used to end in `reload_work`, which rebuilds
  # the map — the beats, the spine, the counts — and not `@page`. But the page
  # is what the read view renders, and it is where a beat becomes a note in
  # the margin beside the paragraph that caused it. So the counts ticked up
  # live while the margin stayed empty until a refresh, which looked like the
  # read had produced nothing.
  #
  # Rebuilt only while the read view is the one on screen. The other tabs get
  # theirs from `load_for_view/1` when they are opened.
  defp live_refresh(socket) do
    socket = reload_work(socket)

    if socket.assigns.view == :read, do: load_page(socket), else: socket
  end

  defp load_map(socket) do
    w = socket.assigns.work

    assign(socket,
      # loaded with the work, not only when the Changes tab is opened: the read
      # view offers its own changes rail and needs to know whether there is
      # anything to offer.
      revisions: Enum.reverse(Works.revisions(w.id)),
      sections: Works.list_sections(w.id),
      beats: Works.list_nodes(w.id, type: "beat"),
      spine: Works.list_nodes(w.id, type: "spine"),
      threads: Works.list_nodes(w.id, type: "thread"),
      questions: Works.list_nodes(w.id, type: "question"),
      counts: Works.counts(w.id)
    )
  end

  defp load_document(socket),
    do: assign(socket, document: Marginalia.Document.get(socket.assigns.work.id))

  defp reload_work(socket) do
    w = Works.get_by_slug(socket.assigns.work.slug)

    socket
    |> assign(work: w, revision_count: Works.revision_count(w.id))
    |> load_map()
  end

  # ==========================================================================
  # Events
  # ==========================================================================

  @impl true
  def handle_event("set_view", %{"view" => v}, socket) do
    socket = assign(socket, view: to_view(v))
    {:noreply, push_patch(socket, to: path(socket), replace: true)}
  end

  # Clicking a note opens the chat already holding that note and the sections
  # it touches, so the writer never has to re-describe what they just pointed at.
  def handle_event("discuss", %{"key" => key}, socket) do
    case Marginalia.Reading.focus(socket.assigns.work, key) do
      nil ->
        {:noreply, socket}

      focus ->
        # path/1 has to be built from the socket that already knows the chat is
        # open, or handle_params reads chat=0 back off the URL and shuts it.
        socket = assign(socket, focus: focus, chat_open: true)
        {:noreply, push_patch(socket, to: path(socket), replace: true)}
    end
  end

  def handle_event("show_help", _params, socket),
    do: {:noreply, assign(socket, tour: Marginalia.Tour.for_view(socket.assigns.view))}

  def handle_event("dismiss_tour", _params, socket), do: {:noreply, assign(socket, tour: nil)}

  def handle_event("clear_focus", _params, socket), do: {:noreply, assign(socket, focus: nil)}

  # A thread, spine node or question carried into the chat with everything it
  # is grounded in — the beats that realise it and the sections they sit in.
  def handle_event("discuss_node", %{"id" => id}, socket) do
    work = socket.assigns.work

    with node_id when is_integer(node_id) <- arg_int(id),
         %{} = node <- Works.get_node(work.id, node_id) do
      g = Marginalia.Reading.grounding(work, node_id)

      focus = %{
        kind: node.node_type,
        title: node.title,
        body:
          [node.body, grounding_note(g)]
          |> Enum.reject(&(&1 in [nil, ""]))
          |> Enum.join(" "),
        quote: node.quote || (List.first(g.beats) || %{}) |> Map.get(:quote),
        sections: g.sections
      }

      socket = assign(socket, focus: focus, chat_open: true)
      {:noreply, push_patch(socket, to: path(socket), replace: true)}
    else
      _ -> {:noreply, socket}
    end
  end

  # --- threads pinned to one paragraph -------------------------------------

  def handle_event("open_thread", %{"ref" => ref} = params, socket) do
    section_id = arg_int(params["section"])
    quote = params["quote"]

    if socket.assigns.demo do
      {:noreply,
       assign(socket,
         open_thread: demo_thread(ref, section_id, quote),
         thread_history: [],
         thread_loading: false
       )}
    else
      open_real_thread(socket, ref, section_id, quote)
    end
  end

  # --- relating this draft to another --------------------------------------

  def handle_event("toggle_linking", _params, socket),
    do: {:noreply, assign(socket, linking?: !socket.assigns.linking?)}

  # One click does the whole thing: pair the two, start the pass that relates
  # their graphs, and go to the page that will fill in as it lands. The page
  # is live, so there is nothing to come back and check.
  def handle_event("link_to", %{"id" => id}, socket) do
    a = socket.assigns

    with true <- a.mine?,
         other when not is_nil(other) <- Works.get_work(a.current_scope.user.id, arg_int(id)),
         {:ok, link} <- Links.get_or_create(a.work.id, other.id) do
      if link.status != "linking", do: Marginalia.Analysis.Linker.start(link, a.provider)

      {:noreply,
       socket
       |> assign(linking?: false)
       |> push_navigate(to: ~p"/links/#{link.id}?lead=#{a.work.slug}")}
    else
      _ -> {:noreply, put_flash(socket, :error, "That draft can't be linked.")}
    end
  end

  # --- the walkthrough ------------------------------------------------------

  # While this is on, the four handlers that would write something or spend a
  # model call answer from `Marginalia.Walkthrough` instead. The controls are
  # the real ones and the events are really dispatched — only the far end is
  # a fixture, which is the whole trick: the writer sees the actual interface
  # respond, on their actual draft, and ends with the draft untouched.
  def handle_event("start_walk", _params, socket) do
    {:noreply,
     socket
     |> assign(
       walk: Walkthrough.steps(socket.assigns.view, mine?: socket.assigns.mine?),
       demo: true,
       tour: nil
     )
     |> mark_walk_seen()}
  end

  # The last step presses this. Seeing the thread, the rewrite and the open
  # editor disappear is the proof of the claim on the card — telling someone
  # nothing was kept while three fixtures sit on the page behind you is not
  # a demonstration of anything.
  def handle_event("walk_reset", _params, socket) do
    {:noreply,
     socket
     |> assign(
       open_thread: nil,
       thread_history: [],
       thread_loading: false,
       rewrite: nil,
       rewriting: false,
       rewrite_ref: nil,
       preview: nil,
       editing: nil,
       edit_text: nil,
       only: nil
     )
     |> load_page()}
  end

  def handle_event("end_walk", _params, socket) do
    {:noreply,
     assign(socket,
       walk: [],
       demo: false,
       open_thread: nil,
       thread_history: [],
       thread_loading: false,
       rewrite: nil,
       rewriting: false,
       rewrite_ref: nil,
       preview: nil,
       editing: nil,
       edit_text: nil
     )}
  end

  # --- rewrites of one selected span ---------------------------------------

  def handle_event("suggest_rewrite", %{"text" => text} = params, socket) do
    a = socket.assigns

    cond do
      # the permission check comes first on purpose: the walkthrough stubs
      # the model, it does not widen what this reader is allowed to do
      not a.mine? ->
        {:noreply, put_flash(socket, :error, "This draft is someone else's.")}

      a.demo ->
        Process.send_after(self(), :demo_rewrite, 1_200)

        {:noreply,
         assign(socket,
           rewriting: true,
           rewrite: nil,
           preview: nil,
           steer: nil,
           rewrite_span: text,
           rewrite_ref: params["ref"]
         )}

      not Chat.allowed?(a.current_scope.user) ->
        {:noreply, assign(socket, quota: 0)}

      a.rewriting ->
        {:noreply, socket}

      true ->
        work = a.work
        provider = a.provider

        {:noreply,
         socket
         |> assign(
           rewriting: true,
           rewrite: nil,
           preview: nil,
           steer: nil,
           rewrite_span: text,
           rewrite_ref: params["ref"]
         )
         |> start_async(:rewrite, fn ->
           Marginalia.Rewrite.propose(work, text, provider: provider)
         end)}
    end
  end

  # The same span again, with the writer saying what they actually want. Kept
  # separate from "suggest_rewrite" because the first pass is one click off a
  # selection and asking for a brief up front would put a form in the way of it.
  def handle_event("steer_rewrite", %{"steer" => steer}, socket) do
    a = socket.assigns
    steer = String.trim(steer || "")

    cond do
      not a.mine? ->
        {:noreply, put_flash(socket, :error, "This draft is someone else's.")}

      a.rewriting or is_nil(a.rewrite_span) or steer == "" ->
        {:noreply, socket}

      a.demo ->
        Process.send_after(self(), :demo_rewrite, 1_200)
        {:noreply, assign(socket, rewriting: true, rewrite: nil, preview: nil)}

      not Chat.allowed?(a.current_scope.user) ->
        {:noreply, assign(socket, quota: 0)}

      true ->
        work = a.work
        provider = a.provider
        span = a.rewrite_span

        {:noreply,
         socket
         |> assign(rewriting: true, rewrite: nil, preview: nil, steer: steer)
         |> start_async(:rewrite, fn ->
           Marginalia.Rewrite.propose(work, span, provider: provider, steer: steer)
         end)}
    end
  end

  def handle_event("dismiss_applied", _params, socket),
    do: {:noreply, assign(socket, applied: nil)}

  def handle_event("toggle_changes", _params, socket),
    do: {:noreply, assign(socket, changes_on: not socket.assigns.changes_on)}

  # The summaries, as something to write from rather than only to read.
  def handle_event("summaries_to_draft", _params, socket) do
    a = socket.assigns

    if a.mine? do
      case Marginalia.Document.to_draft(a.current_scope.user.id, a.work) do
        {:ok, draft} ->
          {:noreply,
           socket
           |> put_flash(:info, "Opened the summaries as a draft of their own.")
           |> push_navigate(to: ~p"/works/#{draft.slug}")}

        {:error, :nothing_summarised} ->
          {:noreply, put_flash(socket, :error, "Summarise at least one section first.")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Could not make a draft: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "This draft is someone else's.")}
    end
  end

  # The whole document: the section summaries fanned out, then two prongs
  # concurrently. Its own commit, because "summarise the document" is a point
  # a writer will want to come back to.
  def handle_event("summarise_document", _params, socket) do
    a = socket.assigns

    cond do
      not a.mine? ->
        {:noreply, put_flash(socket, :error, "This draft is someone else's.")}

      a.demo ->
        {:noreply, put_flash(socket, :info, "The walkthrough does not call the model.")}

      not Chat.allowed?(a.current_scope.user) ->
        {:noreply, assign(socket, quota: 0)}

      a.doc_running ->
        {:noreply, socket}

      true ->
        work = a.work
        provider = a.provider

        {:noreply,
         socket
         |> assign(doc_running: true)
         |> start_async(:document, fn -> Marginalia.Document.run(work, provider: provider) end)}
    end
  end

  # One section, on request. A draft here can be a hundred and eleven
  # documents; summarising all of them unasked is a bill nobody agreed to.
  def handle_event("summarise", %{"ordinal" => ordinal}, socket) do
    a = socket.assigns

    cond do
      not a.mine? ->
        {:noreply, put_flash(socket, :error, "This draft is someone else's.")}

      a.demo ->
        {:noreply, put_flash(socket, :info, "The walkthrough does not call the model.")}

      not Chat.allowed?(a.current_scope.user) ->
        {:noreply, assign(socket, quota: 0)}

      true ->
        n = String.to_integer(ordinal)
        provider = a.provider

        case Works.get_section(a.work.id, n) do
          nil ->
            {:noreply, socket}

          section ->
            {:noreply,
             socket
             |> assign(summarising: MapSet.put(a.summarising, n))
             |> start_async({:summary, n}, fn ->
               Marginalia.Summary.run(section, provider: provider)
             end)}
        end
    end
  end

  # Replace the selection with a candidate, whatever it spans.
  #
  # This was refused for a multi-paragraph span on the grounds that the editor
  # writes one paragraph at a time. That was the wrong constraint: the editor
  # does, but `Works.replace_block/4` works on the section body and replaces
  # any substring of it, so a span crossing four paragraphs was always
  # replaceable. It refuses on :moved if the text has changed underneath,
  # which is the check that matters, and it records a revision either way — so
  # this is undoable in the Changes tab and in git.
  def handle_event("apply_rewrite", %{"i" => i}, socket) do
    a = socket.assigns

    with true <- a.mine?,
         false <- a.demo,
         %{original: original, section: section, candidates: candidates} <- a.rewrite,
         {n, _} <- Integer.parse(to_string(i)),
         %{} = chosen <- Enum.at(candidates, n) do
      section = Works.get_section(a.work.id, section.ordinal) || section

      case Works.replace_block(section, original, chosen.text,
             origin: "rewrite",
             note: chosen.move
           ) do
        {:ok, %{superseded: supers}} ->
          socket =
            socket
            |> assign(
              rewrite: nil,
              preview: nil,
              rewrite_ref: nil,
              rewrite_span: nil,
              steer: nil,
              applied: %{before: original, after: chosen.text}
            )
            |> reload_work()
            |> load_page()

          commit_draft(socket, a, "rewrite")

          {:noreply,
           socket
           |> put_flash(
             :info,
             "Replaced. #{if supers > 0, do: supersede_note(supers), else: "It is in the Changes tab if you want it back."}"
           )}

        {:error, :moved} ->
          {:noreply,
           socket
           |> assign(rewrite: nil, preview: nil)
           |> load_page()
           |> put_flash(
             :error,
             "That passage changed underneath the rewrite. Nothing was replaced."
           )}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Could not replace it: #{inspect(reason)}")}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("preview_rewrite", %{"i" => i}, socket) do
    with %{} = r <- socket.assigns.rewrite,
         %{} = c <- Enum.at(r.candidates, arg_int(i) || -1) do
      {:noreply, assign(socket, preview: %{original: r.original, text: c.text})}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("clear_preview", _params, socket), do: {:noreply, assign(socket, preview: nil)}

  # --- editing one paragraph -----------------------------------------------

  def handle_event("edit_block", %{"ref" => ref} = params, socket) do
    if socket.assigns.mine? do
      block = block_source(socket.assigns.page, ref)

      # "start from this" on a rewrite seeds the box with the candidate, so
      # the writer answers it in their own words rather than from a blank line
      seed = params["seed"]

      case if is_binary(seed) and seed != "",
             do: seeded(block, socket.assigns, seed),
             else: {:ok, block} do
        {:ok, text} ->
          {:noreply, assign(socket, editing: ref, edit_text: text, rewrite: nil, preview: nil)}

        :not_here ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "That rewrite covers more than this paragraph, so it cannot be dropped into it. " <>
               "Copy the version you want, or select inside one paragraph and rewrite again."
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel_edit", _params, socket),
    do: {:noreply, assign(socket, editing: nil, edit_text: nil)}

  def handle_event("save_block", %{"text" => text}, socket) do
    a = socket.assigns

    if a.demo do
      {:noreply,
       socket
       |> assign(editing: nil, edit_text: nil)
       |> put_flash(:info, "Nothing was saved — the walkthrough does not touch your draft.")}
    else
      save_block_for_real(socket, text)
    end
  end

  def handle_event("close_rewrite", _params, socket),
    do: {:noreply, assign(socket, rewrite: nil, preview: nil, rewriting: false, rewrite_ref: nil)}

  def handle_event("close_thread", _params, socket),
    do: {:noreply, assign(socket, open_thread: nil, thread_history: [], thread_loading: false)}

  def handle_event("resolve_thread", _params, %{assigns: %{open_thread: t}} = socket)
      when not is_nil(t) do
    {:ok, thread} = Chat.resolve_thread(t, is_nil(t.resolved_at))

    {:noreply,
     assign(socket,
       open_thread: thread,
       block_threads: Chat.threads_by_block(socket.assigns.work.id)
     )}
  end

  def handle_event("resolve_thread", _params, socket), do: {:noreply, socket}

  def handle_event("thread_send", %{"message" => text}, socket) do
    text = String.trim(text)
    a = socket.assigns

    cond do
      text == "" or a.thread_loading or is_nil(a.open_thread) ->
        {:noreply, socket}

      not a.mine? ->
        {:noreply, socket}

      a.demo ->
        # the delay is not theatre: without it the answer is already there
        # before the question has finished rendering, which reads as a canned
        # page rather than a conversation
        Process.send_after(self(), :demo_reply, 1_100)

        {:noreply,
         assign(socket,
           thread_history: a.thread_history ++ [%{"role" => "user", "content" => text}],
           thread_loading: true
         )}

      not Chat.allowed?(a.current_scope.user) ->
        {:noreply, assign(socket, quota: 0)}

      true ->
        thread = a.open_thread
        history = a.thread_history ++ [%{"role" => "user", "content" => text}]
        Chat.append(thread.id, "user", text)

        # the paragraph is the subject, so it goes in as the focus rather
        # than leaving the model to search for what "this" means
        focus = thread_focus(a.work, thread)
        opts = [provider: a.provider, mode: thread.mode, focus: focus]
        window = Chat.context_window(history)
        work = a.work

        {:noreply,
         socket
         |> assign(
           thread_history: history,
           thread_loading: true,
           quota: Chat.remaining(a.current_scope.user),
           block_threads: Chat.threads_by_block(work.id)
         )
         |> push_event("chat:clear", %{})
         |> start_async(:thread_ask, fn -> Editor.ask(work, window, opts) end)}
    end
  end

  # A passage the writer picked out of their own page, carried into the next
  # question. Verified against the draft before it is kept, so what reaches
  # the model is the manuscript's own characters and not whatever the
  # selection happened to pick up from the markup.
  def handle_event("add_context", %{"text" => text}, socket) do
    case Marginalia.Reading.cite(socket.assigns.work, text) do
      nil ->
        {:noreply, socket}

      cite ->
        cited = Enum.uniq_by(socket.assigns.cited ++ [cite], & &1.text)
        {:noreply, socket |> assign(cited: Enum.take(cited, 6), chat_open: true)}
    end
  end

  def handle_event("drop_context", %{"i" => i}, socket) do
    {:noreply, assign(socket, cited: List.delete_at(socket.assigns.cited, arg_int(i) || -1))}
  end

  def handle_event("new_chat", _params, socket) do
    {:ok, convo} = Chat.create_conversation(socket.assigns.work.id, socket.assigns.mode)
    {:noreply, switch_to(socket, convo)}
  end

  def handle_event("switch_chat", %{"id" => id}, socket) do
    case Chat.get_conversation(socket.assigns.work.id, arg_int(id)) do
      nil -> {:noreply, socket}
      convo -> {:noreply, switch_to(socket, convo)}
    end
  end

  def handle_event("delete_chat", %{"id" => id}, socket) do
    with convo when not is_nil(convo) <-
           Chat.get_conversation(socket.assigns.work.id, arg_int(id)),
         {:ok, _} <- Chat.delete_conversation(convo) do
      {:ok, next} = Chat.get_or_create_conversation(socket.assigns.work.id)
      {:noreply, switch_to(socket, next)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set_only", %{"only" => only}, socket) do
    only = if only in ["", "all"], do: nil, else: only
    {:noreply, socket |> assign(only: only) |> load_page()}
  end

  def handle_event("toggle_chat", _params, socket) do
    socket = assign(socket, chat_open: !socket.assigns.chat_open)
    {:noreply, push_patch(socket, to: path(socket), replace: true)}
  end

  # Everything below this line either spends model credit or changes the
  # draft. Holding the link is permission to read, not to act, so each one is
  # checked here rather than only hidden in the template — a crafted event
  # from a visitor would otherwise run it anyway.
  def handle_event(event, _params, %{assigns: %{mine?: false}} = socket)
      when event in ~w(build_graph start_read send set_mode set_provider) do
    {:noreply,
     put_flash(socket, :error, "This draft is someone else's. You can read it, not change it.")}
  end

  def handle_event("build_graph", _params, socket) do
    DecisionGraph.start(socket.assigns.work, provider: socket.assigns.provider)
    {:noreply, assign(socket, graph_building: true, events: [], event_stats: nil)}
  end

  def handle_event("start_read", _params, socket) do
    work = socket.assigns.work
    # a retry after a failed read starts clean; otherwise the second run's
    # nodes land on top of whatever the first one managed
    if work.status == "read", do: Works.reset_read(work.id)

    Analysis.start(work, socket.assigns.provider)

    {:noreply,
     socket
     |> assign(
       work: %{work | status: "reading"},
       graph_json: nil,
       stages: %{sections: :start, spine: :waiting, weave: :waiting},
       started_at: System.system_time(:second)
     )
     |> load_map()}
  end

  # Admin only, and re-checked in Accounts — a crafted post from a normal
  # user cannot switch backends.
  def handle_event("set_provider", %{"provider" => p}, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.set_llm_provider(user, p) do
      {:ok, updated} ->
        provider = Accounts.provider_for(updated)

        {:noreply,
         socket
         |> assign(provider: provider, llm_ready: Marginalia.LLM.configured?(provider))
         |> put_flash(:info, "Backend: #{provider || "deploy default"}")}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("set_mode", %{"mode" => mode}, socket) do
    {:ok, convo} = Chat.set_mode(socket.assigns.conversation, mode)

    {:noreply,
     assign(socket,
       conversation: convo,
       mode: convo.mode,
       chat_open: true
     )}
  end

  def handle_event("send", %{"message" => text}, socket) do
    text = String.trim(text)
    a = socket.assigns

    cond do
      text == "" or a.loading ->
        {:noreply, socket}

      # checked here rather than only in the template: a crafted event from a
      # closed composer would otherwise spend a question anyway
      not Chat.allowed?(a.current_scope.user) ->
        {:noreply, assign(socket, quota: 0)}

      true ->
        history = a.history ++ [%{"role" => "user", "content" => text}]
        Chat.append(a.conversation.id, "user", text)
        window = Chat.context_window(history)
        work = a.work
        opts = [provider: a.provider, mode: a.mode, focus: a.focus, cited: a.cited]

        {:noreply,
         socket
         |> assign(history: history, draft: "", loading: true, chat_open: true)
         |> push_event("chat:clear", %{})
         |> assign(
           quota: Chat.remaining(a.current_scope.user),
           cited: [],
           threads_list: Chat.conversation_summaries(a.work.id)
         )
         |> start_async(:ask, fn -> Editor.ask(work, window, opts) end)}
    end
  end

  # What the model is told this thread is about: the paragraph in full, the
  # selected passage if there is one, and the section around it.
  defp thread_focus(_work, thread) do
    section =
      thread.section_id && Marginalia.Repo.get(Marginalia.Works.Section, thread.section_id)

    %{
      kind: if(thread.quote, do: "passage", else: "paragraph"),
      title: "A thread pinned to one place in the draft",
      body:
        "The writer opened this thread on a single #{if thread.quote, do: "passage", else: "paragraph"}. " <>
          "Stay on it. Quote it back, say what it is doing and not doing, and propose what would have to " <>
          "change — in their terms, without writing the replacement.",
      quote: thread.quote,
      sections: Enum.reject([section], &is_nil/1)
    }
  end

  @impl true
  def handle_async(:document, result, socket) do
    socket = assign(socket, doc_running: false)

    case result do
      {:ok, {:ok, _doc}} ->
        socket = socket |> reload_work() |> load_page() |> load_document()
        commit_draft(socket, socket.assigns, "summarised")
        {:noreply, put_flash(socket, :info, "The whole document has been read.")}

      {:ok, {:error, reason}} ->
        {:noreply,
         put_flash(socket, :error, "Could not summarise the document: #{inspect(reason)}")}

      {:exit, reason} ->
        {:noreply, put_flash(socket, :error, "The document pass crashed: #{inspect(reason)}")}
    end
  end

  def handle_async({:summary, n}, result, socket) do
    socket = assign(socket, summarising: MapSet.delete(socket.assigns.summarising, n))

    case result do
      {:ok, {:ok, _section}} ->
        {:noreply, load_page(socket)}

      {:ok, {:error, reason}} ->
        {:noreply,
         put_flash(socket, :error, "Could not summarise section #{n}: #{inspect(reason)}")}

      {:exit, reason} ->
        {:noreply, put_flash(socket, :error, "The summary crashed: #{inspect(reason)}")}
    end
  end

  def handle_async(:rewrite, {:ok, {:ok, result}}, socket) do
    {:noreply, assign(socket, rewrite: result, rewriting: false)}
  end

  def handle_async(:rewrite, {:ok, {:error, reason}}, socket) do
    # log what was actually selected: "that is not in the draft" is only
    # actionable if you can see what "that" was
    require Logger

    Logger.warning(
      "marginalia: rewrite refused (#{inspect(reason)}) for work #{socket.assigns.work.id}: " <>
        inspect(String.slice(socket.assigns[:rewrite_span] || "", 0, 300))
    )

    {:noreply,
     socket
     |> assign(rewriting: false)
     |> put_flash(:error, rewrite_error(reason))}
  end

  def handle_async(:rewrite, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(rewriting: false)
     |> put_flash(:error, "That did not go through: #{inspect(reason)}")}
  end

  def handle_async(:thread_ask, {:ok, {:ok, reply}}, socket) do
    if t = socket.assigns.open_thread do
      Chat.append(t.id, "assistant", reply)
    end

    {:noreply,
     assign(socket,
       thread_history:
         socket.assigns.thread_history ++ [%{"role" => "assistant", "content" => reply}],
       thread_loading: false,
       block_threads: Chat.threads_by_block(socket.assigns.work.id)
     )}
  end

  def handle_async(:thread_ask, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(thread_loading: false)
     |> put_flash(:error, "That did not go through: #{inspect(reason)}")}
  end

  def handle_async(:thread_ask, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(thread_loading: false)
     |> put_flash(:error, "That did not go through: #{inspect(reason)}")}
  end

  def handle_async(:ask, {:ok, {:ok, reply}}, socket) do
    Chat.append(socket.assigns.conversation.id, "assistant", reply)

    {:noreply,
     assign(socket,
       history: socket.assigns.history ++ [%{"role" => "assistant", "content" => reply}],
       loading: false
     )}
  end

  def handle_async(:ask, {:ok, {:error, reason}}, socket) do
    {:noreply,
     assign(socket,
       history:
         socket.assigns.history ++
           [%{"role" => "assistant", "content" => "I hit an error: #{reason}"}],
       loading: false
     )}
  end

  def handle_async(:ask, {:exit, reason}, socket) do
    {:noreply,
     assign(socket,
       history:
         socket.assigns.history ++
           [%{"role" => "assistant", "content" => "Something crashed: #{inspect(reason)}"}],
       loading: false
     )}
  end

  # ==========================================================================
  # Live progress
  # ==========================================================================

  @impl true
  def handle_info({:stage, which, state}, socket) do
    {:noreply,
     socket
     |> assign(stages: Map.put(socket.assigns.stages, which, state))
     |> live_refresh()}
  end

  def handle_info({:status, _status}, socket), do: {:noreply, live_refresh(socket)}
  def handle_info({:section, _id, _status}, socket), do: {:noreply, live_refresh(socket)}
  def handle_info({:nodes, _sid, _n}, socket), do: {:noreply, live_refresh(socket)}
  def handle_info({:synthesis, :done}, socket), do: {:noreply, live_refresh(socket)}

  def handle_info({:graph, :done}, socket),
    do:
      {:noreply,
       socket |> assign(graph_building: false) |> reload_work() |> load_graph() |> load_trace()}

  # only pay for the reload when the trace is the thing on screen
  def handle_info({:graph, :event}, socket) do
    if socket.assigns.view == :trace do
      {:noreply, load_trace(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:graph, :failed}, socket),
    do: {:noreply, assign(socket, graph_building: false)}

  def handle_info({:graph, _}, socket), do: {:noreply, socket}
  # The two fixtures the walkthrough answers with. Both are guarded on `demo`
  # as well as being unreachable otherwise, because a stray message that
  # dropped canned prose into a real thread would be the worst bug this file
  # could have.
  def handle_info(:demo_reply, %{assigns: %{demo: true}} = socket) do
    {_question, answer} = Walkthrough.exchange()

    {:noreply,
     assign(socket,
       thread_loading: false,
       thread_history:
         socket.assigns.thread_history ++ [%{"role" => "assistant", "content" => answer}]
     )}
  end

  def handle_info(:demo_rewrite, %{assigns: %{demo: true}} = socket),
    do: {:noreply, assign(socket, rewriting: false, rewrite: Walkthrough.rewrite())}

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp open_real_thread(socket, ref, section_id, quote) do
    case Chat.thread_for_block(socket.assigns.work.id, section_id, ref, quote: quote) do
      {:ok, thread} ->
        {:noreply,
         socket
         |> assign(
           open_thread: thread,
           thread_history: Chat.history(thread.id),
           thread_loading: false,
           block_threads: Chat.threads_by_block(socket.assigns.work.id)
         )}

      _ ->
        {:noreply, socket}
    end
  end

  defp save_block_for_real(socket, text) do
    a = socket.assigns

    with true <- a.mine?,
         ref when is_binary(ref) <- a.editing,
         %{block: block, section: section} <- block_and_section(a.page, ref),
         {:ok, %{superseded: n}} <-
           Works.replace_block(section, block, text, origin: origin(a), note: rewrite_note(a)) do
      socket =
        socket
        |> assign(editing: nil, edit_text: nil, applied: %{before: block, after: text})
        |> reload_work()
        |> load_page()

      # After the transaction, never inside it: a commit is a filesystem side
      # effect that cannot roll back with the database, and one describing a
      # write that never landed is worse than no history at all.
      commit_draft(socket, a, origin(a))

      {:noreply,
       socket
       |> then(fn s -> if n > 0, do: put_flash(s, :info, supersede_note(n)), else: s end)}
    else
      {:error, :empty} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "An empty paragraph is a deletion. Select it and cut it instead."
         )}

      {:error, :moved} ->
        {:noreply,
         socket
         |> assign(editing: nil, edit_text: nil)
         |> load_page()
         |> put_flash(:error, "That paragraph changed underneath the edit. Nothing was saved.")}

      _ ->
        {:noreply, assign(socket, editing: nil, edit_text: nil)}
    end
  end

  # A saved paragraph that started from a rewrite candidate is a rewrite; one
  # typed from scratch is an edit. The panel is closed by `edit_block` before
  # the save, so the origin is taken from what seeded the box.
  defp origin(%{rewrite: %{}}), do: "rewrite"
  defp origin(_), do: "edit"

  defp rewrite_note(%{rewrite: %{candidates: _}, preview: %{move: move}}) when is_binary(move),
    do: move

  defp rewrite_note(_), do: nil

  defp commit_draft(socket, assigns, origin) do
    if Marginalia.Git.enabled?() do
      work = socket.assigns.work
      who = assigns.current_scope.user

      Task.Supervisor.start_child(Marginalia.TaskSupervisor, fn ->
        Marginalia.Git.commit(work, "#{origin}: #{work.title}",
          author: "#{who.email} <#{who.email}>"
        )
      end)
    end

    :ok
  end

  # A conversation struct that is never inserted. `inline_thread` only reads
  # fields, so an unsaved one renders exactly like a real thread.
  defp demo_thread(ref, section_id, quote) do
    %Marginalia.Chat.Conversation{
      id: 0,
      block_ref: ref,
      section_id: section_id,
      anchor_kind: if(quote, do: "span", else: "block"),
      quote: quote,
      mode: Editor.default_mode()
    }
  end

  defp mark_walk_seen(socket) do
    scope = socket.assigns.current_scope
    view = to_string(socket.assigns.view)

    if ((connected?(socket) and scope) && scope.user &&
          view in Walkthrough.views()) and not Accounts.seen_tour?(scope.user, "walk:" <> view) do
      case Accounts.mark_tour_seen(scope.user, "walk:" <> view) do
        {:ok, user} -> assign(socket, current_scope: %{scope | user: user})
        _ -> socket
      end
    else
      socket
    end
  end

  # ==========================================================================
  # Render
  # ==========================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="w-full px-6 py-6">
        <div class="flex items-baseline gap-3 flex-wrap">
          <h1 style="font-family:var(--mg-serif)" class="text-2xl font-semibold tracking-tight">
            {@work.title}
          </h1>
          <span class="mg-meta">
            {@work.word_count} words · {length(@sections)} sections · {@counts.beats} beats
          </span>
          <div class="ml-auto flex gap-2 items-baseline flex-wrap">
            <.links_control
              :if={@mine? and @work.status == "read"}
              work={@work}
              links={@links}
              open={@linking?}
              others={Links.linkable(@current_scope.user.id, @work.id)}
            />

            <%= if @mine? and @work.status == "read" and @counts.beats == 0 do %>
              <button class="mg-btn sm" phx-click="start_read">Read again</button>
            <% end %>
          </div>
        </div>

        <%!-- A draft can be related to several others, and a relationship
              that only appears inside a dropdown is one nobody remembers
              they made. --%>
        <div :if={@links != []} class="mg-linkrow">
          <span class="mg-label">read alongside</span>
          <.link :for={l <- @links} navigate={~p"/links/#{l.id}?lead=#{@work.slug}"} class="one">
            <span class="t">{Links.other(l, @work.id).title}</span>
            <span :if={l.status != "linked"} class={["st", l.status]}>{l.status}</span>
          </.link>
        </div>

        <div class="mt-5 flex items-baseline gap-5 flex-wrap border-b border-[var(--mg-rule)] pb-0">
          <div class="mg-tabs">
            <.tab view={@view} this={:read} label="Read" />
            <.tab view={@view} this={:graph} label="Graph" />
            <.tab view={@view} this={:spine} label="Spine" />
            <.tab view={@view} this={:threads} label="Threads" />
            <%!-- only offered once there is something to show --%>
            <.tab :if={@revision_count > 0} view={@view} this={:changes} label="Changes" />
            <%!-- how the thing works, not what it found: mine to look at --%>
            <.tab :if={@owner?} view={@view} this={:trace} label="Trace" />
            <.tab :if={@owner?} view={@view} this={:prompts} label="Prompts" />
          </div>

          <button
            class="mg-help"
            phx-click="show_help"
            title="What is this tab for?"
            aria-label="What is this tab for?"
          >?</button>

          <div class="ml-auto flex items-baseline gap-3 pb-1">
            <%= if @mine? do %>
              <button
                class="mg-btn sm ghost"
                id="share-link"
                phx-hook=".Share"
                data-url={url(~p"/works/#{@work.slug}")}
              >Copy link</button>
            <% else %>
              <span class="mg-badge">reading someone's draft</span>
            <% end %>
            <button
              class={"mg-btn sm" <> if(@chat_open, do: "", else: " ghost")}
              phx-click="toggle_chat"
            >Talk about it</button>
            <%= if @owner? and length(@backends) > 1 do %>
              <form phx-change="set_provider" class="inline-flex items-baseline gap-1.5">
                <span class="mg-label">backend</span>
                <select
                  name="provider"
                  class="text-[0.72rem] bg-transparent border border-[var(--mg-rule)] rounded-sm px-1.5 py-0.5"
                >
                  <%= for b <- @backends do %>
                    <option
                      value={b.name}
                      selected={
                        to_string(b.name) == (@provider || to_string(Marginalia.LLM.provider_name()))
                      }
                    >
                      {b.label}
                    </option>
                  <% end %>
                </select>
                <span class="mg-meta opacity-60">
                  {Enum.find(
                    @backends,
                    &(to_string(&1.name) == (@provider || to_string(Marginalia.LLM.provider_name())))
                  ).model}
                </span>
              </form>
            <% end %>
          </div>
        </div>

        <div
          class={"mt-5 relative " <> if(@chat_open, do: "mg-shifted", else: "")}
          id="page-body"
          phx-hook=".Selection"
        >
          <div id="sel-actions" hidden>
            <button id="sel-discuss" type="button">Discuss this</button>
            <button id="sel-rewrite" type="button">Suggest a rewrite</button>
            <button id="sel-add" type="button">Add to question</button>
          </div>
          <div class="min-w-0">
            <%= case @work.status do %>
              <% "pending" -> %>
                <.confirm_gate
                  sections={@sections}
                  llm_ready={@llm_ready}
                  provider={@provider}
                  mine?={@mine?}
                />
              <% _ -> %>
                <.tour_card :if={@tour} tour={@tour} walk?={Walkthrough.for_view?(@view)} />
                <MarginaliaWeb.Walk.overlay :if={@walk != []} steps={@walk} />

                <%= if @work.status == "reading" do %>
                  <.progress
                    sections={@sections}
                    counts={@counts}
                    stages={@stages}
                    started_at={@started_at}
                  />
                <% end %>
                <.map_view
                  view={@view}
                  work={@work}
                  diff_rows={@diff_rows}
                  diff_stat={@diff_stat}
                  revisions={@revisions}
                  summarising={@summarising}
                  document={@document}
                  doc_running={@doc_running}
                  changes_on={@changes_on}
                  applied={@applied}
                  graph_json={@graph_json}
                  graph_stats={@graph_stats}
                  passes={@passes}
                  modes={@modes}
                  graph_building={@graph_building}
                  events={@events}
                  event_stats={@event_stats}
                  page={@page}
                  only={@only}
                  mine?={@mine?}
                  collapsed={@chat_open}
                  block_threads={@block_threads}
                  open_thread={@open_thread}
                  rewrite={@rewrite}
                  rewriting={@rewriting}
                  rewrite_ref={@rewrite_ref}
                  steer={@steer}
                  rewrite_span={@rewrite_span}
                  preview={@preview}
                  editing={@editing}
                  edit_text={@edit_text}
                  thread_history={@thread_history}
                  thread_loading={@thread_loading}
                  sections={@sections}
                  beats={@beats}
                  spine={@spine}
                  threads={@threads}
                  questions={@questions}
                />
            <% end %>
          </div>
        </div>

        <div class={"mg-drawer " <> if(@chat_open, do: "open", else: "")} aria-hidden={not @chat_open}>
          <%= if @chat_open do %>
            <.chat_panel
              history={@history}
              loading={@loading}
              status={@work.status}
              llm_ready={@llm_ready}
              provider={@provider}
              mode={@mode}
              modes={@modes}
              focus={@focus}
              quota={@quota}
              mine?={@mine?}
              threads_list={@threads_list}
              conversation={@conversation}
              cited={@cited}
            />
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :view, :atom, required: true
  attr :this, :atom, required: true
  attr :label, :string, required: true

  defp tab(assigns) do
    ~H"""
    <button
      class={"mg-tab" <> if(@view == @this, do: " on", else: "")}
      phx-click="set_view"
      phx-value-view={Atom.to_string(@this)}
    >{@label}</button>
    """
  end

  attr :sections, :list, required: true
  attr :llm_ready, :boolean, required: true
  attr :provider, :string, default: nil
  attr :mine?, :boolean, default: true

  defp confirm_gate(assigns) do
    ~H"""
    <div>
      <h2 class="mg-label">Before it reads</h2>
      <p class="mg-prose mt-2.5 max-w-[62ch] text-[0.95rem]">
        This is how the draft has been divided. A machine guessing your section breaks is a
        machine getting everything after that wrong, so have a look before anything is read.
      </p>

      <%!-- The action goes above the list, not below it.
            It was below, and the one draft a stranger left sitting
            unread for two days was the one with the most sections —
            twenty-five rows, which is about eight hundred pixels, which
            put the only button on the page under the fold. The list is
            there to be checked, not read: whoever wants to check it can
            scroll, and whoever does not should not have to. --%>
      <div :if={@llm_ready and @mine?} class="mt-5 flex items-baseline gap-3 flex-wrap">
        <button class="mg-btn" phx-click="start_read">
          Read it — {length(@sections)} sections
        </button>
        <span class="mg-hint mt-0">
          Takes a few minutes. Everything else on the page stays usable while it runs.
        </span>
      </div>

      <div
        :if={not (@llm_ready and @mine?)}
        class="mt-5 text-[0.85rem] border-l-2 border-[var(--mg-accent)] pl-3 py-1.5"
      >
        No {Marginalia.LLM.label(@provider)} key is configured on this deploy, so the read can't run.
      </div>

      <div class="mg-rows mt-5 max-w-[62ch]">
        <%= for s <- @sections do %>
          <div class="mg-row">
            <span class="n">{s.ordinal}</span>
            <span class="flex-1 min-w-0 truncate text-[0.9rem]">{s.title}</span>
            <span class="mg-meta">{s.word_count}w</span>
          </div>
        <% end %>
      </div>

      <%!-- and again at the end, for anyone who did read to the bottom --%>
      <button
        :if={@llm_ready and @mine? and length(@sections) > 8}
        class="mg-btn mt-5"
        phx-click="start_read"
      >
        Read it — {length(@sections)} sections
      </button>
    </div>
    """
  end

  attr :sections, :list, required: true
  attr :counts, :map, required: true
  attr :stages, :map, default: %{}
  attr :started_at, :integer, default: nil

  # A read is three different jobs that take about a minute each, and the last
  # of them produces nothing visible until it is finished. A row of badges
  # left the writer watching a still page for the final minute with no way to
  # tell working from hung. So: name the three, say which one is running, and
  # show what each has actually found.
  defp progress(assigns) do
    ~H"""
    <div class="border-b border-[var(--mg-rule)] pb-6 mb-7">
      <div class="flex items-baseline gap-3">
        <h2 class="mg-label">Reading your draft</h2>
        <span
          :if={@started_at}
          id="read-clock"
          phx-hook=".Clock"
          data-since={@started_at}
          class="mg-meta"
        >0:00</span>
        <span class="mg-hint mt-0 ml-auto">Everything else on the page stays usable.</span>
      </div>

      <div class="mt-4 grid gap-y-3 max-w-[58ch]" style="grid-template-columns:1.4rem 11rem 1fr">
        <.stage
          state={stage_of(@stages, :sections)}
          name="Sections"
          detail={
            "#{Enum.count(@sections, &(&1.status == "read"))} of #{length(@sections)} read" <>
              if(@counts.beats > 0, do: " · #{@counts.beats} beats", else: "")
          }
        />
        <.stage
          state={stage_of(@stages, :spine)}
          name="The spine"
          detail={
            if @counts.spine > 0 do
              "#{@counts.spine} spine · #{@counts.threads} threads · #{@counts.questions} questions"
            else
              "what the whole draft hangs off"
            end
          }
        />
        <.stage
          state={stage_of(@stages, :weave)}
          name="Connections"
          detail="what develops, pays off, requires, or contradicts what"
        />
      </div>

      <div :if={stage_of(@stages, :sections) == :start} class="mt-5 flex flex-wrap gap-1.5">
        <span :for={s <- @sections} class={"mg-badge " <> status_class(s.status)}>
          {s.ordinal}
        </span>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".Clock">
        // Counts up from when the read started. Server-side ticking would mean
        // a message a second per viewer to render a number nobody acts on.
        export default {
          mounted() { this.tick(); this.t = setInterval(() => this.tick(), 1000); },
          destroyed() { clearInterval(this.t); },
          tick() {
            const since = Number(this.el.dataset.since);
            if (!since) return;
            const s = Math.max(0, Math.floor(Date.now() / 1000) - since);
            this.el.textContent = Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
          },
        };
      </script>
    </div>
    """
  end

  attr :state, :atom, required: true
  attr :name, :string, required: true
  attr :detail, :string, required: true

  defp stage(assigns) do
    ~H"""
    <span class={[
      "text-[0.8rem] leading-6",
      @state == :done && "text-[var(--mg-accent)]",
      @state == :start && "text-[var(--mg-ink)]",
      @state == :waiting && "text-[var(--mg-dim)] opacity-40"
    ]}>
      <%= case @state do %>
        <% :done -> %>
          ✓
        <% :failed -> %>
          ✕
        <% :start -> %>
          <span class="mg-dot inline-block" style="background:var(--mg-accent)"></span>
        <% _ -> %>
          ·
      <% end %>
    </span>
    <span class={[
      "text-[0.8rem] leading-6",
      @state == :waiting && "text-[var(--mg-dim)] opacity-50",
      @state == :start && "font-semibold"
    ]}>{@name}</span>
    <span class={[
      "text-[0.8rem] leading-6 text-[var(--mg-dim)]",
      @state == :waiting && "opacity-50"
    ]}>{@detail}</span>
    """
  end

  defp grounding_note(%{beats: []}), do: nil

  defp grounding_note(%{beats: beats}) do
    "It runs through " <>
      Enum.map_join(beats, "; ", fn b ->
        "section #{b.section && b.section.ordinal}: #{b.title}"
      end) <> "."
  end

  defp supersede_note(1), do: "One note was about the line you changed. It is greyed, not gone."

  defp supersede_note(n),
    do: "#{n} notes were about lines you changed. They are greyed, not gone."

  defp block_source(page, ref) do
    case block_and_section(page, ref) do
      %{block: block} -> block
      _ -> ""
    end
  end

  defp block_and_section(page, ref) do
    Enum.find_value(page || [], fn sec ->
      Enum.find_value(sec.blocks, fn b ->
        b.ref == ref && %{block: b.text, section: sec.section}
      end)
    end)
  end

  # the candidate, dropped into the paragraph where the original sat, so the
  # writer edits their own line rather than staring at a replacement
  # `:not_here` rather than a guess. This used to fall through to `seed`,
  # which replaced the WHOLE paragraph with a rewrite of text that was not in
  # it — the panel anchored to a paragraph the span did not cover, and one
  # click silently overwrote it. A rewrite that cannot be placed is a refusal,
  # not a substitution.
  defp seeded(block, assigns, seed) do
    case assigns.rewrite do
      %{original: original} -> Marginalia.Rewrite.place(block, original, seed)
      _ -> {:ok, seed}
    end
  end

  defp rewrite_error(:not_in_draft),
    do: "That selection is not in the draft, character for character."

  defp rewrite_error({:span_too_long, words, max}),
    do:
      "That is #{words} words. Rewrites go up to #{max} — past that, split it and take " <>
        "the part you actually want reworked."

  defp rewrite_error(:no_candidates),
    do: "Nothing came back that was different from what you wrote."

  defp rewrite_error(other), do: "That did not go through: #{inspect(other)}"

  defp stage_of(stages, key), do: Map.get(stages || %{}, key, :waiting)

  defp arg_int(n) when is_integer(n), do: n

  defp arg_int(n) when is_binary(n) do
    case Integer.parse(n) do
      {i, _} -> i
      :error -> nil
    end
  end

  defp arg_int(_), do: nil

  # A reload mid-read gets no broadcasts for the stages that already finished,
  # so the state is read back off what is in the database instead of resetting
  # the writer's view to "nothing has happened yet".
  defp infer_stages(work) do
    counts = Works.counts(work.id)
    sections = Works.list_sections(work.id)
    all_read? = sections != [] and Enum.all?(sections, &(&1.status in ["read", "failed"]))

    cond do
      work.status == "read" ->
        %{sections: :done, spine: :done, weave: :done}

      work.status != "reading" ->
        %{sections: :waiting, spine: :waiting, weave: :waiting}

      counts.spine > 0 ->
        %{sections: :done, spine: :done, weave: :start}

      all_read? ->
        %{sections: :done, spine: :start, weave: :waiting}

      true ->
        %{sections: :start, spine: :waiting, weave: :waiting}
    end
  end

  defp status_class("read"), do: "ink"
  defp status_class("failed"), do: "accent"
  defp status_class("reading"), do: "accent"
  defp status_class(_), do: ""

  attr :view, :atom, required: true
  attr :work, :map, required: true
  attr :graph_json, :string, default: nil
  attr :graph_stats, :map, default: nil
  attr :passes, :list, default: []
  attr :modes, :list, default: []
  attr :graph_building, :boolean, default: false
  attr :events, :list, default: []
  attr :event_stats, :map, default: nil
  attr :page, :list, default: nil
  attr :only, :string, default: nil
  attr :mine?, :boolean, default: true
  attr :collapsed, :boolean, default: false
  attr :block_threads, :map, default: %{}
  attr :open_thread, :map, default: nil
  attr :thread_history, :list, default: []
  attr :thread_loading, :boolean, default: false
  attr :rewrite, :map, default: nil
  attr :rewriting, :boolean, default: false
  attr :rewrite_ref, :string, default: nil
  attr :steer, :string, default: nil
  attr :rewrite_span, :string, default: nil
  attr :preview, :map, default: nil
  attr :editing, :string, default: nil
  attr :edit_text, :string, default: nil
  attr :sections, :list, required: true
  attr :beats, :list, required: true
  attr :spine, :list, required: true
  attr :threads, :list, required: true
  attr :questions, :list, required: true
  attr :diff_rows, :list, default: []
  attr :diff_stat, :map, default: nil
  attr :revisions, :list, default: []
  attr :summarising, :any, default: nil
  attr :document, :any, default: nil
  attr :doc_running, :boolean, default: false
  attr :changes_on, :boolean, default: false
  attr :applied, :any, default: nil

  defp map_view(assigns) do
    ~H"""
    <div>
      <%= case @view do %>
        <% :spine -> %>
          <%= if @work.first_impression do %>
            <h2 class="mg-label">First impression</h2>
            <p class="mg-prose mt-2.5 max-w-[78ch]">{@work.first_impression}</p>
          <% end %>

          <p
            :if={@work.status_detail}
            class="mt-3 text-[0.8rem] border-l-2 border-[var(--mg-accent)] pl-2.5 py-1 text-[var(--mg-dim)]"
          >
            {@work.status_detail}
          </p>

          <h2 class={"mg-label" <> if(@work.first_impression, do: " mt-12", else: "")}>The spine</h2>
          <p class="mg-hint">The chain the whole draft hangs off, in order.</p>
          <%= if @spine == [] do %>
            <p class="mg-empty mt-4">No spine was produced for this draft.</p>
          <% else %>
            <div class="mg-cards mt-5">
              <.grounded_node
                :for={{n, i} <- Enum.with_index(@spine, 1)}
                node={n}
                work={@work}
                mine?={@mine?}
                n={String.pad_leading(to_string(i), 2, "0")}
              />
            </div>
          <% end %>

          <%= if @questions != [] do %>
            <h2 class="mg-label mt-12">Questions this raised</h2>
            <p class="mg-hint">
              Each names something specific in the draft. In the page view they are attached
              to the paragraphs they are about.
            </p>
            <div class="mg-cards mt-4">
              <.grounded_node :for={q <- @questions} node={q} work={@work} mine?={@mine?} />
            </div>
          <% end %>
        <% :changes -> %>
          <.changes_pane
            rows={@diff_rows}
            stat={@diff_stat}
            revisions={@revisions}
            work={@work}
          />
        <% :graph -> %>
          <.graph_pane
            work={@work}
            graph_json={@graph_json}
            stats={@graph_stats}
            building={@graph_building}
            mine?={@mine?}
          />
        <% :read -> %>
          <.read_pane
            page={@page}
            slug={@work.slug}
            changes_on={@changes_on}
            revisions={@revisions}
            applied={@applied}
            summarising={@summarising}
            document={@document}
            doc_running={@doc_running}
            words={@work.word_count}
            only={@only}
            collapsed={@collapsed}
            block_threads={@block_threads}
            open_thread={@open_thread}
            thread_history={@thread_history}
            thread_loading={@thread_loading}
            mine?={@mine?}
            modes={@modes}
            rewrite={@rewrite}
            rewriting={@rewriting}
            rewrite_ref={@rewrite_ref}
            steer={@steer}
            rewrite_span={@rewrite_span}
            preview={@preview}
            editing={@editing}
            edit_text={@edit_text}
          />
        <% :trace -> %>
          <.trace_pane work={@work} events={@events} stats={@event_stats} building={@graph_building} />
        <% :prompts -> %>
          <.prompts_pane passes={@passes} modes={@modes} />
        <% :threads -> %>
          <h2 class="mg-label">Threads</h2>
          <p class="mg-hint">Patterns that run across sections rather than happening in one.</p>
          <%= if @threads == [] do %>
            <p class="mg-empty mt-4">No threads were identified.</p>
          <% else %>
            <div class="mg-cards mt-5">
              <.grounded_node :for={t <- @threads} node={t} work={@work} mine?={@mine?} />
            </div>
          <% end %>
      <% end %>
    </div>
    """
  end

  attr :work, :map, required: true
  attr :graph_json, :string, default: nil
  attr :stats, :map, default: nil
  attr :building, :boolean, default: false
  attr :mine?, :boolean, default: true

  defp graph_pane(assigns) do
    ~H"""
    <div>
      <div class="flex items-baseline gap-3 flex-wrap">
        <h2 class="mg-label">Knowledge graph</h2>
        <%= if @stats do %>
          <span class="mg-meta">
            {@stats.nodes} nodes · {@stats.edges} edges · {@stats.anchored} anchored
          </span>
        <% end %>
        <div class="ml-auto flex gap-2 items-baseline">
          <%= cond do %>
            <% @building -> %>
              <span class="text-[0.75rem] italic text-[var(--mg-dim)]">building the decision graph…</span>
            <% @mine? -> %>
              <button class="mg-btn sm" phx-click="build_graph">Build decision graph</button>
            <% true -> %>
              <span></span>
          <% end %>
          <a href={~p"/works/#{@work.slug}/graph.json"} class="mg-btn sm ghost">graph.json</a>
          <a href={~p"/works/#{@work.slug}/graph.dot"} class="mg-btn sm ghost">graph.dot</a>
        </div>
      </div>

      <div class="mt-2.5 flex items-baseline gap-4 flex-wrap">
        <div class="mg-legend">
          <span><i style="background:#8a3324"></i>goal</span>
          <span><i style="background:#b45309"></i>option</span>
          <span><i style="background:#1e3a8a"></i>decision</span>
          <span><i style="background:#166534"></i>action</span>
          <span><i style="background:#0891b2"></i>outcome</span>
          <span><i style="background:#6b665e"></i>observation</span>
          <span><i style="background:#7c2d92"></i>revisit</span>
        </div>
        <span class="mg-hint mt-0">solid = leads to · dotted = develops / pays off / requires / tension</span>
      </div>

      <%= if @graph_json do %>
        <div class="mg-card mg-graph mt-3.5" style="height:calc(100vh - 17rem); min-height:26rem">
          <div
            id="graph-canvas"
            phx-hook=".LaneTree"
            phx-update="ignore"
            data-graph={@graph_json}
            class="mg-graph-canvas"
          >
            <svg id="graph-svg"></svg>
          </div>
          <div class="mg-graph-detail" id="graph-detail">
            <p class="mg-empty">Pick a node to see what it says and why it is there.</p>
          </div>
        </div>
      <% end %>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".LaneTree">
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

        export default {
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
        };
      </script>
    </div>
    """
  end

  attr :tour, :map, required: true
  attr :walk?, :boolean, default: false

  # One card, shown the first time a tab is opened. Every point here exists
  # because the affordance it names is invisible until someone says it: a
  # hairline in the gutter, a highlight you can hover, a filter that changes
  # what the margin is about.
  defp tour_card(assigns) do
    ~H"""
    <div class="mg-tour">
      <div class="flex items-baseline gap-3">
        <h2 style="font-family:var(--mg-serif)" class="text-[1.15rem] font-semibold">
          {@tour.title}
        </h2>
        <button class="mg-btn sm ghost ml-auto" phx-click="dismiss_tour">Got it</button>
      </div>

      <ul class="mg-tour-points">
        <li :for={point <- @tour.points}>{point}</li>
      </ul>

      <%!-- Offered rather than started. Almost everything here is invisible
            until it fires, so being shown beats being told — but firing nine
            controls at somebody who has just handed over a manuscript,
            without asking, is not a demo, it is a fright. --%>
      <div :if={@walk?} class="mg-tour-foot">
        <button class="mg-btn sm" phx-click="start_walk">Show me</button>
        <span class="mg-hint mt-0">
          Works the controls for you. Nothing is saved and the model is never called.
        </span>
      </div>

      <p class="mg-hint mt-2.5">The <strong>?</strong> beside the tabs brings this back.</p>
    </div>
    """
  end

  attr :node, :map, required: true
  attr :work, :map, required: true
  attr :mine?, :boolean, default: true
  attr :n, :string, default: nil

  # A spine node, thread or question with what it is grounded in underneath:
  # the beats that realise it and the sections they sit in. Clicking it takes
  # the whole lot into the chat, so the writer never has to re-explain which
  # thread they meant or go and find where it happens.
  defp grounded_node(assigns) do
    assigns =
      assign(assigns, :grounding, Marginalia.Reading.grounding(assigns.work, assigns.node.id))

    ~H"""
    <div class="mg-grounded">
      <div class="flex items-start gap-3">
        <div class="min-w-0 flex-1">
          <div style="font-family:var(--mg-serif)" class="text-[1.04rem] leading-snug">
            <span :if={@n} class="mg-meta mr-1.5">{@n}</span>{@node.title}
          </div>
          <div :if={@node.body} class="text-[0.8rem] text-[var(--mg-dim)] mt-1 leading-relaxed">
            {@node.body}
          </div>
        </div>

        <button
          :if={@mine?}
          class="mg-btn sm ghost shrink-0"
          phx-click="discuss_node"
          phx-value-id={@node.id}
          title="Open the chat holding this and everywhere it happens"
        >Discuss</button>
      </div>

      <%= if @grounding.beats == [] do %>
        <div class="mg-meta mt-2 opacity-60">not yet linked to anywhere in the draft</div>
      <% else %>
        <div class="mg-where">
          <span class="mg-label">where it happens</span>
          <div :for={b <- @grounding.beats} class="hit">
            <span class="n">{b.section && b.section.ordinal}</span>
            <span class="min-w-0">
              <span class="t">{b.title}</span>
              <span :if={b.quote} class="q">"{Marginalia.Reading.plain(b.quote)}"</span>
            </span>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  attr :rewrite, :map, default: nil
  attr :working, :boolean, default: false
  attr :block_ref, :string, default: nil
  attr :steer, :string, default: nil
  attr :span, :string, default: nil

  attr :rows, :list, required: true
  attr :stat, :map, default: nil
  attr :revisions, :list, default: []
  attr :work, :map, required: true

  @doc false
  # The draft as it arrived beside the draft as it is. Two columns rather
  # than one marked-up copy, because a writer comparing versions is asking
  # "what did I have before", and an inline diff answers a different question.
  def changes_pane(assigns) do
    ~H"""
    <div class="mg-diff">
      <div class="mg-diff-head">
        <span class="mg-label">Changes since it arrived</span>
        <span :if={@stat} class="mg-meta ml-auto">
          {@stat.changed} edited · {@stat.added} added · {@stat.removed} removed
        </span>
      </div>

      <p :if={not Marginalia.Diff.any?(@rows)} class="mg-empty">
        Nothing has changed yet. Edits and applied rewrites show up here.
      </p>

      <.diff_table :if={Marginalia.Diff.any?(@rows)} rows={@rows} left="As it arrived" right="Now" />

      <div :if={@revisions != []} class="mg-diff-log">
        <div class="mg-label">Every change, newest first</div>
        <ol class="mg-rows">
          <li :for={rev <- @revisions}>
            <span class="n">{rev.seq}</span>
            <span class="mg-meta">
              {rev.origin}{if rev.note, do: " — #{rev.note}"} · section {rev.section_ordinal}
            </span>
            <div class="mg-diff-patch">
              <span
                :for={{op, t} <- Marginalia.Diff.words(rev.before, rev.after)}
                class={word_class(op, :new)}
              >{t}</span>
            </div>
          </li>
        </ol>
      </div>
    </div>
    """
  end

  attr :rows, :list, required: true
  attr :left, :string, default: "Before"
  attr :right, :string, default: "After"
  attr :compact, :boolean, default: false

  @doc false
  # Two columns, GitHub's split view: what was there on the left with the
  # removed words struck through in red, what is there now on the right with
  # the added words in green. The counterpart's marks are hidden in each
  # column — showing both in both is how a unified diff reads, and this is
  # not one.
  def diff_table(assigns) do
    ~H"""
    <div class={"mg-diff-cols" <> if(@compact, do: " compact", else: "")}>
      <div class="mg-diff-colhead"><span>{@left}</span><span>{@right}</span></div>

      <div :for={row <- @rows} class={"mg-diff-row " <> row_kind(row)}>
        <%= case row do %>
          <% {:same, l, _} -> %>
            <div class="side old">{l}</div>
            <div class="side new">{l}</div>
          <% {:change, l, r} -> %>
            <div class="side old">
              <span :for={{op, t} <- Marginalia.Diff.words(l, r)} class={word_class(op, :old)}>{t}</span>
            </div>
            <div class="side new">
              <span :for={{op, t} <- Marginalia.Diff.words(l, r)} class={word_class(op, :new)}>{t}</span>
            </div>
          <% {:del, l} -> %>
            <div class="side old gone">{l}</div>
            <div class="side new empty"></div>
          <% {:ins, r} -> %>
            <div class="side old empty"></div>
            <div class="side new fresh">{r}</div>
        <% end %>
      </div>
    </div>
    """
  end

  # The block that now holds what was written. A replacement collapsing three
  # paragraphs into one means the ref that was anchored no longer names the
  # same text, so the text is what identifies it.
  defp landed?(nil, _block), do: false

  defp landed?(%{after: written}, %{text: text}) when is_binary(written) and written != "" do
    String.contains?(text, String.slice(written, 0, 80))
  end

  defp landed?(_applied, _block), do: false

  # While the candidates are still coming back there is no located span yet,
  # so the anchor block is all there is to go on. Once they arrive, `covers`
  # names every paragraph the span touches.
  defp rewriting?(%{covers: covers}, _anchor, ref) when is_list(covers) and covers != [],
    do: ref in covers

  defp rewriting?(_rewrite, anchor, ref), do: anchor == ref

  defp row_kind({:same, _, _}), do: "same"
  defp row_kind({:change, _, _}), do: "change"
  defp row_kind({:del, _}), do: "del"
  defp row_kind({:ins, _}), do: "ins"

  # The old column shows what was removed and hides what replaced it; the new
  # column does the reverse. Showing both marks in both columns is how an
  # inline diff reads, and this is not one.
  defp word_class(:same, _), do: "w"
  defp word_class(:del, :old), do: "w del"
  defp word_class(:del, :new), do: "w hide"
  defp word_class(:ins, :old), do: "w hide"
  defp word_class(:ins, :new), do: "w ins"

  # Candidates for one selected line, side by side with what is there now.
  # Three labelled options rather than one suggestion: a single rewrite reads
  # as the answer, and the point is that the writer chooses.
  defp rewrite_panel(assigns) do
    ~H"""
    <div class={"mg-rewrite" <> if(@working, do: " working", else: "")} id="rewrite-panel">
      <%!-- It said "one line" regardless. A span can now be 2,500 words, the
            panel renders under the FIRST block of a multi-paragraph selection,
            and a writer looking at it had nothing on screen telling them how
            much was about to be replaced. --%>
      <div class="mg-rewrite-head">
        <span class="mg-label">{Marginalia.Rewrite.span_label(@span)}</span>
        <button class="mg-btn sm ghost ml-auto" phx-click="close_rewrite">close</button>
      </div>

      <p :if={Marginalia.Rewrite.span_extent(@span)} class="mg-rw-extent">
        {Marginalia.Rewrite.span_extent(@span)}
      </p>

      <%!-- Optional, and after the fact: the first three come back off one
            click, and this is for when none of them is what was wanted. --%>
      <form class="mg-rw-steer" phx-submit="steer_rewrite">
        <input
          type="text"
          name="steer"
          value={@steer}
          maxlength="400"
          placeholder="ask for something specific — shorter, lead with the finding, drop the hedging"
          disabled={@working}
        />
        <button type="submit" class="mg-btn sm" disabled={@working}>Again</button>
      </form>

      <%!-- an empty box that fills in, rather than a spinner standing where
            the answer will be: the shape of the thing arrives first --%>
      <div :if={@working} class="mg-rewrite-body">
        <div class="mg-dots" aria-label="reading it">
          <span class="mg-dot"></span>
          <span class="mg-dot" style="animation-delay:.18s"></span>
          <span class="mg-dot" style="animation-delay:.36s"></span>
        </div>
      </div>

      <div :if={@rewrite} class="mg-rewrite-body">
        <p :if={@rewrite.reading} class="mg-hint mt-0 mb-2.5">{@rewrite.reading}</p>

        <%!-- A span crossing paragraphs has no one paragraph to be dropped
              into, and the editor writes one paragraph at a time. Saying so
              is better than an action that silently overwrites the wrong one. --%>
        <p :if={@rewrite.spans_blocks} class="mg-hint mt-0 mb-2.5">
          This covers more than one paragraph. Replacing works on the whole passage;
          editing one first needs a selection inside a single paragraph.
        </p>

        <%!-- LiveView has no phx-mouseover: hovering is not one of its
              bindings, so the preview never fired and the legend in the hint
              below was the only ins/del on the page. A hook does it. --%>
        <div class="mg-rw-list" id="rw-list" phx-hook=".Hover">
          <button
            :for={{c, i} <- Enum.with_index(@rewrite.candidates)}
            class="mg-rw"
            style={"--i:#{i}"}
            data-i={i}
          >
            <span class="head">
              <span class="move">{c.move}</span>
              <span :if={c.cost} class="cost">{c.cost}</span>
            </span>
            <span class="words">{c.text}</span>
            <span
              class="mine apply"
              phx-click="apply_rewrite"
              phx-value-i={i}
              data-confirm="Replace the selected passage with this version? It goes in the Changes tab and the draft's git history, so it can be got back."
            >replace the passage with this →</span>

            <span
              :if={not @rewrite.spans_blocks}
              class="mine"
              phx-click="edit_block"
              phx-value-ref={@block_ref}
              phx-value-seed={c.text}
            >or edit it first →</span>
          </button>
        </div>

        <script :type={Phoenix.LiveView.ColocatedHook} name=".Hover">
          // Hover to see a candidate in the line it would replace; the
          // pointer leaving puts the line back. Debounced on the way out so
          // moving between two candidates does not flicker the paragraph.
          export default {
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
          };
        </script>

        <p class="mg-hint mt-2.5">
          The line above is dimmed because these would replace it. Hover one and it shows there
          instead — <ins class="mg-swap">what arrives</ins>
          against <del class="mg-cut">what goes</del>. Nothing is applied.
        </p>
      </div>
    </div>
    """
  end

  attr :thread, :map, required: true
  attr :history, :list, default: []
  attr :loading, :boolean, default: false
  attr :mine?, :boolean, default: true
  attr :modes, :list, default: []

  # One conversation, about one paragraph, opened where that paragraph is.
  # Deliberately not the drawer: the drawer is for the draft, and this is for
  # the sentence in front of you. Keeping them apart is what lets a thread
  # still be here next week when you come back to the same paragraph.
  defp inline_thread(assigns) do
    ~H"""
    <div class="mg-thread-panel" id={"thread-#{@thread.id}"}>
      <div class="mg-thread-head">
        <span class="mg-label">
          {if @thread.anchor_kind == "span", do: "on this passage", else: "on this paragraph"}
        </span>
        <span :if={@thread.resolved_at} class="mg-badge">settled</span>

        <div class="ml-auto flex items-baseline gap-2">
          <button
            :if={@mine? and @history != []}
            class="mg-btn sm ghost"
            phx-click="resolve_thread"
          >{if @thread.resolved_at, do: "reopen", else: "settle"}</button>
          <button class="mg-btn sm ghost" phx-click="close_thread">close</button>
        </div>
      </div>

      <div class="mg-thread-body" id={"thread-body-#{@thread.id}"} phx-hook=".StickToBottom">
        <blockquote :if={@thread.quote} class="mg-thread-quote">"{@thread.quote}"</blockquote>

        <p :if={@history == []} class="text-[0.78rem] text-[var(--mg-dim)] leading-relaxed">
          Ask about this one. What is it doing, what is it not doing, what would have to
          change. It will quote the draft back rather than rewrite it.
        </p>

        <%= for m <- @history do %>
          <%= if m["role"] == "user" do %>
            <div class="mg-thread-turn mine">
              <span class="who">you</span>
              <div class="said">{m["content"]}</div>
            </div>
          <% else %>
            <div class="mg-thread-turn theirs">
              <span class="who">the reader</span>
              <div class="said md">{Marginalia.Markdown.to_html(m["content"])}</div>
            </div>
          <% end %>
        <% end %>

        <div :if={@loading} class="flex gap-1 items-center py-0.5">
          <span class="mg-dot"></span>
          <span class="mg-dot" style="animation-delay:.18s"></span>
          <span class="mg-dot" style="animation-delay:.36s"></span>
        </div>
      </div>

      <div :if={@mine?} class="mg-thread-foot">
        <form phx-submit="thread_send" id={"thread-form-#{@thread.id}"} phx-hook=".Composer">
          <textarea
            name="message"
            rows="2"
            autocomplete="off"
            placeholder="What about this paragraph?"
            class="w-full text-[0.8rem] leading-relaxed resize-none min-h-[3.2rem] max-h-56 px-2.5 py-2 bg-[var(--mg-paper)] border border-[var(--mg-rule)] rounded-sm focus:outline-none focus:border-[var(--mg-accent)]"
            disabled={@loading}
          ></textarea>
          <div class="flex items-center gap-2 mt-1.5">
            <span class="mg-hint mt-0">Enter to send</span>
            <button type="submit" class="mg-btn sm ml-auto" disabled={@loading}>
              {if @loading, do: "…", else: "Ask"}
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  attr :work, :map, required: true
  attr :links, :list, default: []
  attr :open, :boolean, default: false
  attr :others, :list, default: []

  # Linking this draft to another, and the ones already related to it.
  #
  # Only drafts that have been read are offered: the pass relates two
  # graphs, and an unread draft has no graph to relate.
  defp links_control(assigns) do
    ~H"""
    <div class="mg-linkbox" id="linkbox" phx-click-away={@open && JS.push("toggle_linking")}>
      <button class="mg-btn sm ghost" phx-click="toggle_linking">
        Link{if @links != [], do: " · #{length(@links)}"}
      </button>

      <div :if={@open} class="mg-linkmenu">
        <%= if @links != [] do %>
          <span class="mg-label">already linked</span>
          <.link :for={l <- @links} navigate={~p"/links/#{l.id}?lead=#{@work.slug}"} class="row">
            <span class="t">{Links.other(l, @work.id).title}</span>
            <span class={"st " <> l.status}>{l.status}</span>
          </.link>
        <% end %>

        <span class="mg-label">link to</span>
        <%= if @others == [] do %>
          <p class="none">
            Nothing to link to yet. A second draft has to have been read before the two
            can be related — linking works on the maps, not the text.
          </p>
        <% else %>
          <button :for={o <- @others} class="row" phx-click="link_to" phx-value-id={o.id}>
            <span class="t">{o.title}</span>
            <span class="n">{o.word_count}w</span>
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  attr :entries, :list, default: []
  attr :words, :integer, default: nil

  # A map of the draft, parked in the corner. The point of a map is that
  # distance on it means distance in the thing it describes, so every row is
  # sized by its word count: a 1,600-word section gets five times the block a
  # 320-word one does. Collapsed that is a silhouette you can read the shape
  # of the draft off; open it is the same shape, labelled, and you can jump
  # from it. Reading a long draft a paragraph at a time makes it very easy to
  # lose the whole, and scrolling for a section you half remember is the tax
  # on that.
  defp minimap(assigns) do
    entries = assigns.entries
    total = entries |> Enum.map(&(&1.words || 0)) |> Enum.sum() |> max(1)

    # a sub-heading carries no word count of its own, and a very short
    # section would collapse to an unclickable hairline, so every row is
    # floored at roughly a fortieth of the draft
    floor = max(div(total, 40), 1)
    entries = Enum.map(entries, &Map.put(&1, :grow, max(&1.words || 0, floor)))

    # proportions come from the section sums, but the headline number is the
    # work's own: two different word counts on one screen reads as a bug
    assigns = assign(assigns, entries: entries, total: assigns.words || total)

    ~H"""
    <nav :if={length(@entries) > 1} class="mg-map" id="minimap" phx-hook=".Minimap">
      <button class="mg-map-rail" aria-label="Contents" aria-expanded="false">
        <i :for={e <- @entries} class={"t l#{e.level}"} style={"flex-grow:#{e.grow}"}></i>
      </button>

      <div class="mg-map-panel">
        <div class="mg-map-head">
          <span>contents</span>
          <span class="n">{@total} words</span>
        </div>

        <ol class="mg-map-body">
          <li :for={e <- @entries} style={"flex-grow:#{e.grow}"} data-full={e.title}>
            <a href={"##{e.id}"} class={"l#{e.level}"} data-target={e.id}>
              <span class="t">{e.title}</span>
              <span :if={e.words} class="w">{e.words}w</span>
            </a>
          </li>
        </ol>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".Minimap">
        // Open on click, and follow the reader down the page so the block
        // beside where they are is lit. Kept client-side: which heading is
        // on screen changes every few hundred milliseconds and is nobody's
        // business but the browser's.
        export default {
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
        };
      </script>
    </nav>
    """
  end

  attr :page, :list, default: nil
  attr :words, :integer, default: nil
  attr :only, :string, default: nil
  attr :collapsed, :boolean, default: false
  attr :block_threads, :map, default: %{}
  attr :open_thread, :map, default: nil
  attr :thread_history, :list, default: []
  attr :thread_loading, :boolean, default: false
  attr :mine?, :boolean, default: true
  attr :modes, :list, default: []
  attr :rewrite, :map, default: nil
  attr :rewriting, :boolean, default: false
  attr :rewrite_ref, :string, default: nil
  attr :steer, :string, default: nil
  attr :rewrite_span, :string, default: nil
  attr :preview, :map, default: nil
  attr :editing, :string, default: nil
  attr :edit_text, :string, default: nil
  attr :summarising, :any, default: nil
  attr :document, :any, default: nil
  attr :doc_running, :boolean, default: false
  attr :slug, :string, default: nil
  attr :changes_on, :boolean, default: false
  attr :revisions, :list, default: []
  attr :applied, :any, default: nil

  # The draft with its notes in the margin. This is the only view that shows
  # the writer their own prose, and the notes sit beside the paragraph that
  # caused them rather than at the top of a section — which is possible only
  # because every note carries a span verified against the source.
  defp read_pane(assigns) do
    ~H"""
    <div>
      <div class="flex items-baseline gap-4 flex-wrap">
        <h2 class="mg-label">The page</h2>
        <button
          :if={@revisions != []}
          class={"mg-btn sm ghost mg-chg-toggle" <> if(@changes_on, do: " on", else: "")}
          phx-click="toggle_changes"
        >{if @changes_on, do: "Back to the notes", else: "Show what changed"}</button>

        <div class="mg-tabs" id="read-filters">
          <button
            :for={
              {id, label} <- [
                {"all", "Everything"},
                {"beats", "Beats"},
                {"connections", "Connections"},
                {"tensions", "Tensions"}
              ]
            }
            class={"mg-tab" <> if((@only || "all") == id, do: " on", else: "")}
            phx-click="set_only"
            phx-value-only={id}
          >{label}</button>
        </div>
        <span class="mg-hint mt-0 ml-auto">
          Notes sit beside the sentence that caused them. The highlight is the span they are anchored to.
        </span>
      </div>

      <%= if @page in [nil, []] do %>
        <p class="mg-empty mt-6">Nothing read yet.</p>
      <% else %>
        <.minimap entries={Marginalia.Reading.outline(@page)} words={@words} />

        <div
          class={"mg-read mt-6" <> if(@collapsed, do: " collapsed", else: "")}
          id="read-rail"
          phx-hook=".MarginNotes"
        >
          <div :if={@mine?} class="mg-doc">
            <div class="mg-doc-head">
              <span class="mg-label">The whole document</span>

              <%!-- Only once there is something to make one out of. A draft
                    built from no summaries is an empty draft. --%>
              <button
                :if={Enum.any?(@page || [], &(&1.section.summary not in [nil, ""]))}
                class="mg-btn sm ghost ml-auto"
                phx-click="summaries_to_draft"
                title="Make a draft out of the summaries, to edit and read like any other"
              >Open as a draft</button>

              <button
                class="mg-btn sm ghost"
                phx-click="summarise_document"
                disabled={@doc_running}
              >
                {cond do
                  @doc_running -> "Reading it all…"
                  @document -> "Read it again"
                  true -> "Summarise the document"
                end}
              </button>
            </div>

            <div :if={@document} class="mg-doc-body">
              <p class="mg-doc-summary">{@document.summary}</p>
              <p :if={@document.throughline} class="mg-doc-through">{@document.throughline}</p>

              <div :if={@document.movements != []} class="mg-doc-moves">
                <span class="mg-label">how it moves</span>
                <div :for={m <- @document.movements} class="mg-doc-move">
                  <strong>{m["heading"]}</strong>
                  <span class="mg-meta">
                    §{Enum.join(m["sections"] || [], ", §")}
                  </span>
                  <p>{m["does"]}</p>
                </div>
              </div>

              <div :if={@document.guidelines != []} class="mg-doc-rules">
                <span class="mg-label">what it is working under</span>
                <div :for={g <- @document.guidelines} class="mg-doc-rule">
                  <strong>{g["guideline"]}</strong>
                  <p>{g["because"]}</p>
                  <span class="mg-meta">§{Enum.join(g["sections"] || [], ", §")}</span>
                </div>
              </div>

              <div :if={@document.tensions != []} class="mg-doc-rules tensions">
                <span class="mg-label">where those pull against each other</span>
                <div :for={t <- @document.tensions} class="mg-doc-rule">
                  <p>{t["tension"]}</p>
                  <span class="mg-meta">§{Enum.join(t["sections"] || [], ", §")}</span>
                </div>
              </div>

              <p :if={@document.dropped != []} class="mg-sum-stale">
                {length(@document.dropped)} claim(s) dropped: {Enum.join(@document.dropped, "; ")}
              </p>
            </div>
          </div>

          <div
            class="mg-read-body"
            id="read-body"
            phx-hook=".SummaryVault"
            data-editable={to_string(@mine?)}
          >
            <%= for sec <- @page do %>
              <div class="mg-read-head" id={"sec-#{sec.section.ordinal}"}>
                <div class="mg-label">Section {sec.section.ordinal}</div>
                <h2 style="font-family:var(--mg-serif)" class="text-[1.45rem] font-semibold mt-1">
                  {sec.section.title}
                </h2>

                <%!-- What the section says, for finding your place in twelve
                      of them. Per section and on request: a draft here can be
                      a hundred and eleven documents. --%>
                <div :if={@mine?} class="mg-sum">
                  <%!-- The server keeps one summary per section: re-running
                        overwrites it, and the text that was there is gone. The
                        vault below keeps the last few in this browser so a
                        re-run is undoable by the person who ran it. --%>
                  <div
                    :if={sec.section.summary}
                    class={"mg-sum-text" <> if(Marginalia.Summary.current?(sec.section), do: "", else: " stale")}
                    data-sum-key={"#{@slug}:#{sec.section.ordinal}"}
                    data-sum-at={
                      sec.section.summarised_at && DateTime.to_iso8601(sec.section.summarised_at)
                    }
                    data-sum-text={sec.section.summary}
                  >
                    {sec.section.summary}

                    <div :if={sec.section.summary_covers != []} class="mg-sum-covers">
                      <span :for={t <- sec.section.summary_covers}>{t}</span>
                    </div>

                    <div
                      :if={sec.section.summary_follows != [] or sec.section.summary_sets_up}
                      class="mg-sum-links"
                    >
                      <span :if={sec.section.summary_follows != []}>
                        needs {Enum.map_join(sec.section.summary_follows, ", ", &"§#{&1}")}
                      </span>
                      <span :if={sec.section.summary_sets_up}>
                        sets up: {sec.section.summary_sets_up}
                      </span>
                    </div>

                    <span :if={not Marginalia.Summary.current?(sec.section)} class="mg-sum-stale">
                      the section has been edited since this was written
                    </span>

                    <%!-- Not only that it went stale but what moved under it,
                          which is what decides whether it is worth running
                          again. --%>
                    <.diff_table
                      :if={Marginalia.Summary.drift(sec.section) != []}
                      rows={Marginalia.Summary.drift(sec.section)}
                      left="When it was summarised"
                      right="Now"
                      compact
                    />

                    <span :if={sec.section.summary_dropped != []} class="mg-sum-stale">
                      {length(sec.section.summary_dropped)} term(s) dropped: not in the section
                    </span>
                  </div>

                  <%!-- phx-update="ignore": the hook owns what is in here, and
                        a LiveView patch would wipe it on the next broadcast. --%>
                  <div
                    :if={sec.section.summary}
                    id={"sumvault-#{sec.section.ordinal}"}
                    class="mg-sum-vault"
                    phx-update="ignore"
                  >
                  </div>

                  <button
                    class="mg-btn sm ghost"
                    phx-click="summarise"
                    phx-value-ordinal={sec.section.ordinal}
                    disabled={MapSet.member?(@summarising, sec.section.ordinal)}
                  >
                    <%= cond do %>
                      <% MapSet.member?(@summarising, sec.section.ordinal) -> %>
                        Summarising…
                      <% sec.section.summary -> %>
                        Summarise again
                      <% true -> %>
                        Summarise this section
                    <% end %>
                  </button>
                </div>
              </div>

              <%= for b <- sec.blocks do %>
                <% t = @block_threads[b.ref] %>
                <div
                  class={
                    [
                      "mg-block",
                      t && "has-thread",
                      t && t.resolved && "resolved",
                      @open_thread && @open_thread.block_ref == b.ref && "open",
                      # every paragraph the span covers, not only the one the
                      # panel is anchored to: a rewrite of three paragraphs
                      # dimmed one and left the other two looking untouched
                      (@rewriting or @rewrite) && is_nil(@preview) &&
                        rewriting?(@rewrite, @rewrite_ref, b.ref) && "rewriting"
                    ]
                  }
                  id={"block-#{b.ref}"}
                >
                  <button
                    class="mg-tick"
                    phx-click="open_thread"
                    phx-value-ref={b.ref}
                    phx-value-section={sec.section.id}
                    aria-label={
                      if t, do: "Open the thread on this paragraph", else: "Talk about this paragraph"
                    }
                    title={
                      if t,
                        do: "#{t.messages} in this thread",
                        else: "Talk about this paragraph"
                    }
                  ></button>
                  <%= if @editing == b.ref do %>
                    <form
                      phx-submit="save_block"
                      id={"edit-#{b.ref}"}
                      phx-hook=".Editor"
                      class="mg-edit"
                    >
                      <textarea name="text" rows="3" spellcheck="true">{@edit_text}</textarea>
                      <div class="foot">
                        <span class="mg-hint mt-0">
                          This is the paragraph's markdown. ⌘↵ saves · Esc cancels
                        </span>
                        <button type="button" class="mg-btn sm ghost" phx-click="cancel_edit">cancel</button>
                        <button type="submit" class="mg-btn sm">Save</button>
                      </div>
                    </form>
                  <% else %>
                    <%!-- The paragraph the change landed in shows what it
                          replaced, in place, until it is dismissed. Matched on
                          the text rather than on the ref because replacing
                          three paragraphs with one renumbers every ref after
                          it. --%>
                    <%= if landed?(@applied, b) do %>
                      <div class="mg-applied">
                        <div class="mg-applied-head">
                          <span class="mg-label">replaced</span>
                          <button class="mg-btn sm ghost ml-auto" phx-click="dismiss_applied">
                            done
                          </button>
                        </div>

                        <.diff_table
                          rows={[{:change, @applied.before, @applied.after}]}
                          left="Before"
                          right="Now"
                          compact
                        />
                      </div>
                    <% else %>
                      {Marginalia.Reading.render_block(b.text, b.mark, b.ref, @preview)}
                    <% end %>
                  <% end %>
                </div>

                <%!-- With the rail given over to the diff, a note has nowhere
                      to sit in the margin, so it sits under its own paragraph. --%>
                <div :if={@changes_on and b.notes != []} class="mg-note-inline">
                  <button
                    :for={n <- b.notes}
                    class={"mg-note " <> n.kind}
                    phx-click="discuss"
                    phx-value-key={n.key}
                  >
                    <span class="who">{String.replace(n.kind, "_", " ")}</span>
                    <span class="said">{n.title}</span>
                  </button>
                </div>

                <.rewrite_panel
                  :if={(@rewriting or @rewrite) && @rewrite_ref == b.ref}
                  rewrite={@rewrite}
                  working={@rewriting}
                  block_ref={b.ref}
                  steer={@steer}
                  span={@rewrite_span}
                />

                <.inline_thread
                  :if={@open_thread && @open_thread.block_ref == b.ref}
                  thread={@open_thread}
                  history={@thread_history}
                  loading={@thread_loading}
                  mine?={@mine?}
                  modes={@modes}
                />
              <% end %>
            <% end %>
          </div>

          <%!-- What changed, where the notes usually are. The notes do not
                disappear: they move into the prose column beside the paragraph
                that caused them, so the rail is free for the before and after. --%>
          <div :if={@changes_on} class="mg-read-rail changes">
            <p :if={@revisions == []} class="mg-empty">
              Nothing has been changed yet.
            </p>

            <div :for={rev <- @revisions} class="mg-chg">
              <span class="mg-label">
                {rev.origin}{if rev.note, do: " — #{rev.note}"} · section {rev.section_ordinal}
              </span>
              <div class="mg-chg-old">
                <span
                  :for={{op, t} <- Marginalia.Diff.words(rev.before, rev.after)}
                  class={word_class(op, :old)}
                >{t}</span>
              </div>
              <div class="mg-chg-new">
                <span
                  :for={{op, t} <- Marginalia.Diff.words(rev.before, rev.after)}
                  class={word_class(op, :new)}
                >{t}</span>
              </div>
            </div>
          </div>

          <div :if={not @changes_on} class="mg-read-rail">
            <%= for sec <- @page do %>
              <div :for={n <- sec.unplaced} class="mg-note-slot">
                <button class={"mg-note " <> n.kind} phx-click="discuss" phx-value-key={n.key}>
                  <span class="who">{String.replace(n.kind, "_", " ")} · not located</span>
                  <span class="said">{n.title}</span>
                  <span :if={n.body} class="why">{n.body}</span>
                </button>
              </div>

              <%= for b <- sec.blocks, n <- b.notes do %>
                <div class={"mg-note-slot " <> n.kind} data-anchor={b.ref}>
                  <button
                    class={"mg-note " <> n.kind}
                    phx-click="discuss"
                    phx-value-key={n.key}
                    title="Talk about this"
                  >
                    <span class="who">{String.replace(n.kind, "_", " ")}</span>
                    <span class="said">{n.title}</span>
                    <span :if={n.body} class="why">{n.body}</span>
                  </button>
                </div>
              <% end %>
            <% end %>
          </div>

          <script :type={Phoenix.LiveView.ColocatedHook} name=".Editor">
            // The paragraph's markdown, in place. Not a rich text editor: the
            // page is rendered from this source and every note is anchored into
            // it, so round-tripping HTML back to markdown would quietly move
            // every anchor in the section.
            export default {
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
            };
          </script>

          <script :type={Phoenix.LiveView.ColocatedHook} name=".Selection">
            // Select a passage and both things you can do with it appear at the
            // end of it: talk about that spot in its own thread, or carry it into
            // the question you are already writing. Two different intentions, and
            // guessing which one someone meant gets it wrong half the time.
            //
            // The text is verified against the manuscript server-side before
            // either path keeps it: a browser selection picks up whatever the
            // markup puts in its way.
            export default {
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
            };
          </script>

          <script :type={Phoenix.LiveView.ColocatedHook} name=".Share">
            // The link is the permission, so handing it over has to be one click.
            export default {
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
            };
          </script>

          <script :type={Phoenix.LiveView.ColocatedHook} name=".SummaryVault">
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

            export default {
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
            };
          </script>

          <script :type={Phoenix.LiveView.ColocatedHook} name=".MarginNotes">
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
            export default {
              mounted() {
                this.pinned = new Set();
                this.showing = new Map();
                this.layout();
                this.watch();
              },
              updated() { this.layout(); },
              destroyed() {
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

                this.el.querySelectorAll(".mg-note-slot").forEach((slot) => {
                  const id = slot.dataset.anchor;
                  const mark = id && this.el.querySelector(`#anchor-${CSS.escape(id)}`);
                  if (!mark) return;
                  slot.addEventListener("mouseenter", () => mark.classList.add("lit"));
                  slot.addEventListener("mouseleave", () => mark.classList.remove("lit"));
                });

                this.el.querySelectorAll(".mg-read-body mark[id]").forEach((mark) => {
                  const ref = mark.id.replace(/^anchor-/, "");
                  mark.addEventListener("mouseenter", () => this.collapsed() && this.peek(ref, mark));
                  mark.addEventListener("mouseleave", () => this.collapsed() && this.unpeek(ref));
                  mark.addEventListener("click", (e) => {
                    if (!this.collapsed()) return;
                    e.stopPropagation();
                    if (this.pinned.has(ref)) { this.pinned.delete(ref); this.unpeek(ref); }
                    else { this.pinned.add(ref); this.peek(ref, mark); }
                    mark.classList.toggle("pinned", this.pinned.has(ref));
                  });
                });

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
              },
            };
          </script>
        </div>
      <% end %>
    </div>
    """
  end

  attr :work, :map, required: true
  attr :events, :list, required: true
  attr :stats, :map, default: nil
  attr :building, :boolean, default: false

  # The build, as it happened. Refusals are kept and shown rather than hidden,
  # because "the server said no and the model corrected itself" is the evidence
  # that the flow rule and the anchoring guarantee are real and not decorative.
  defp trace_pane(assigns) do
    ~H"""
    <div>
      <div class="flex items-baseline gap-3 flex-wrap">
        <h2 class="mg-label">Build trace</h2>
        <%= if @stats && @stats.calls > 0 do %>
          <span class="mg-meta">{@stats.calls} tool calls · {@stats.refused} refused</span>
        <% end %>
        <div class="ml-auto flex gap-2 items-baseline">
          <%= if @building do %>
            <span class="text-[0.75rem] italic text-[var(--mg-dim)]">building…</span>
          <% end %>
          <a href={~p"/works/#{@work.slug}/trace.json"} class="mg-btn sm ghost">trace.json</a>
        </div>
      </div>

      <p class="mg-hint mt-2 max-w-[68ch]">
        Every call the model made to <code>add_node</code>, <code>link</code>
        and <code>set_status</code>
        — the deciduous CLI, handed over as functions — and what the
        server answered. Red lines are refusals: a quote that was not in your draft, or a link
        that broke <code>goal → option → decision → action → outcome</code>.
      </p>

      <%= if @stats && @stats.refused > 0 do %>
        <div class="mt-3 flex gap-2 flex-wrap">
          <%= for {kind, n} <- @stats.refusals do %>
            <span class="mg-badge accent">{kind} × {n}</span>
          <% end %>
        </div>
      <% end %>

      <%= if @events == [] do %>
        <p class="mg-empty mt-6">
          Nothing recorded yet. Build the decision graph from the Graph tab and this fills in live.
        </p>
      <% else %>
        <div class="mg-trace mt-4">
          <%= for {narrative, group} <- Enum.chunk_by(@events, & &1.narrative) |> Enum.map(&{List.first(&1).narrative, &1}) do %>
            <div class="mt-5 first:mt-0">
              <div class="mg-label mb-1">{narrative}</div>
              <%= for e <- group do %>
                <div class={"call" <> if(e.ok, do: "", else: " no")}>
                  <span class="seq">{e.seq}</span>
                  <span class="tool">{e.tool}</span>
                  <span class="min-w-0 break-words">
                    {summarise_args(e)}
                    <%= if not e.ok do %>
                      <span class="why">↳ {refusal_text(e)}</span>
                    <% end %>
                  </span>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # The trace is only useful if it is skimmable, so each call renders as the one
  # line it would have been at a shell prompt.
  defp summarise_args(%{tool: "add_node", args: args}) do
    a = decode(args)
    "#{a["type"]}  #{a["title"]}"
  end

  defp summarise_args(%{tool: "link", args: args}) do
    a = decode(args)
    "#{a["from"]} → #{a["to"]}#{if a["rationale"], do: "  (#{a["rationale"]})", else: ""}"
  end

  defp summarise_args(%{tool: "set_status", args: args}) do
    a = decode(args)
    "#{a["id"]} → #{a["status"]}"
  end

  defp summarise_args(%{args: args}), do: String.slice(args || "", 0, 160)

  defp refusal_text(%{result: result}) do
    case decode(result) do
      %{"error" => e} -> e
      _ -> String.slice(result || "", 0, 200)
    end
  end

  defp decode(nil), do: %{}

  defp decode(json) do
    case Jason.decode(json) do
      {:ok, m} when is_map(m) -> m
      _ -> %{}
    end
  end

  attr :passes, :list, required: true
  attr :modes, :list, required: true

  defp prompts_pane(assigns) do
    ~H"""
    <div>
      <h2 class="mg-label">How the graph was built</h2>
      <p class="mt-2 text-xs opacity-60 max-w-prose">
        The exact prompts that ran against your draft, read out of the running code rather than
        retyped here — so this page cannot drift from what actually happened.
      </p>

      <%= for p <- @passes do %>
        <div class="mt-6">
          <div class="flex items-baseline gap-2 flex-wrap">
            <h3 style="font-family:var(--mg-serif)" class="font-semibold text-[1.05rem]">{p.name}</h3>
            <span class="mg-meta">{p.model}</span>
          </div>
          <div class="mg-hint mt-0.5">{p.runs} · produces {p.produces}</div>
          <pre class="mt-2.5 text-[0.74rem] leading-relaxed whitespace-pre-wrap bg-[var(--mg-margin)] border border-[var(--mg-rule)] rounded-sm p-3.5 overflow-x-auto max-w-[80ch]">{p.prompt}</pre>
        </div>
      <% end %>

      <h2 class="mg-label mt-12">How the chat is steered</h2>
      <p class="mt-2 text-xs opacity-60 max-w-prose">
        Every conversation carries the same system prompt; the stance below is appended last,
        depending on which mode you are in.
      </p>
      <%= for m <- @modes do %>
        <div class="mt-5">
          <h3 style="font-family:var(--mg-serif)" class="font-semibold text-[1.05rem]">
            {m.label} <span class="font-normal text-[var(--mg-dim)]">— {m.blurb}</span>
          </h3>
          <pre class="mt-2.5 text-[0.74rem] leading-relaxed whitespace-pre-wrap bg-[var(--mg-margin)] border border-[var(--mg-rule)] rounded-sm p-3.5 overflow-x-auto max-w-[80ch]">{m.stance}</pre>
        </div>
      <% end %>
    </div>
    """
  end

  attr :history, :list, required: true
  attr :loading, :boolean, required: true
  attr :status, :string, required: true
  attr :llm_ready, :boolean, required: true
  attr :mode, :string, required: true
  attr :modes, :list, required: true
  attr :provider, :string, default: nil
  attr :focus, :map, default: nil
  attr :quota, :any, default: :unlimited
  attr :mine?, :boolean, default: true
  attr :threads_list, :list, default: []
  attr :conversation, :map, default: nil
  attr :cited, :list, default: []

  defp chat_panel(assigns) do
    ~H"""
    <div class="flex flex-col h-full min-h-0">
      <div class="px-4 pt-3 pb-2.5 shrink-0 bg-[var(--mg-paper)]">
        <div class="flex items-baseline gap-2">
          <span class="mg-label">Talk about it</span>
          <span class="mg-meta opacity-70">{Marginalia.LLM.label(@provider)}</span>
          <button class="mg-btn sm ghost ml-auto" phx-click="toggle_chat" title="Close">Close</button>
        </div>

        <%= if @llm_ready and @status != "pending" do %>
          <div class="mg-tabs mt-2.5">
            <%= for m <- @modes do %>
              <button
                class={"mg-tab" <> if(m.id == @mode, do: " on", else: "")}
                phx-click="set_mode"
                phx-value-mode={m.id}
                title={m.blurb}
              >{m.label}</button>
            <% end %>
          </div>
          <div class="text-[0.72rem] text-[var(--mg-dim)] mt-1.5">
            {Enum.find(@modes, &(&1.id == @mode)).blurb}
          </div>
        <% end %>
      </div>

      <div :if={@mine?} class="mg-threads shrink-0">
        <button class="mg-thread" phx-click="new_chat" title="Start a new thread">+ New</button>
        <button
          :for={t <- @threads_list}
          class={"mg-thread" <> if(@conversation && t.id == @conversation.id, do: " on", else: "")}
          phx-click="switch_chat"
          phx-value-id={t.id}
        >
          <span class="name">{t.title}</span>
          <span class="n">{t.messages}</span>
        </button>
        <button
          :if={@conversation && length(@threads_list) > 1}
          class="mg-thread"
          phx-click="delete_chat"
          phx-value-id={@conversation.id}
          data-confirm="Delete this thread and everything said in it?"
          title="Delete the thread you are in"
        >×</button>
      </div>

      <div
        id="chat-scroll"
        phx-hook=".StickToBottom"
        class="flex-1 overflow-y-auto min-h-0 px-4 py-4 flex flex-col gap-4"
      >
        <%= cond do %>
          <% not @llm_ready -> %>
            <p class="text-sm opacity-60">
              No {Marginalia.LLM.label(@provider)} key configured on this deploy.
            </p>
          <% @status == "pending" -> %>
            <p class="text-sm opacity-60">Confirm the sections and run the read first.</p>
          <% not @mine? and @history == [] -> %>
            <p class="mg-empty">Nothing has been said about this draft yet.</p>
          <% @history == [] -> %>
            <p class="mg-prose text-[0.95rem] text-[var(--mg-dim)]">
              {Marginalia.Chat.Editor.opener(@mode)}
            </p>
          <% true -> %>
            <%= for m <- @history do %>
              <%= if m["role"] == "user" do %>
                <div class="mg-turn-you">{m["content"]}</div>
              <% else %>
                <div class="md">{Marginalia.Markdown.to_html(m["content"])}</div>
              <% end %>
            <% end %>
        <% end %>

        <%= if @loading do %>
          <div class="flex gap-1 items-center py-1" aria-label="thinking">
            <span class="mg-dot"></span>
            <span class="mg-dot" style="animation-delay:.18s"></span>
            <span class="mg-dot" style="animation-delay:.36s"></span>
          </div>
        <% end %>
      </div>

      <%= if not @mine? do %>
        <div class="border-t border-[var(--mg-rule)] p-4 shrink-0 bg-[var(--mg-margin)]">
          <div class="mg-label">Read only</div>
          <p class="text-[0.8rem] mt-1.5 leading-relaxed text-[var(--mg-dim)]">
            You have the link to someone else's draft. You can read everything here — the
            page, the map, what has already been said — but the asking is theirs.
          </p>
        </div>
      <% end %>

      <%= if @mine? and @llm_ready and @status != "pending" and @quota == 0 do %>
        <div class="border-t border-[var(--mg-rule)] p-4 shrink-0 bg-[var(--mg-margin)]">
          <div class="mg-label">Out of questions</div>
          <p class="text-[0.8rem] mt-1.5 leading-relaxed text-[var(--mg-dim)]">
            This deploy gives every account {Marginalia.Chat.message_limit()} questions. The
            read, the graph and everything already said stay where they are.
          </p>
        </div>
      <% end %>

      <%= if @mine? and @llm_ready and @status != "pending" and @quota != 0 do %>
        <div class="border-t border-[var(--mg-rule)] p-3 shrink-0 bg-[var(--mg-paper)]">
          <div :if={@focus} class="mg-holding">
            <div class="flex items-start gap-2">
              <div class="min-w-0 flex-1">
                <div class="mg-label">holding · {String.replace(@focus.kind, "_", " ")}</div>
                <div class="text-[0.8rem] mt-1 leading-snug font-medium">{@focus.title}</div>
              </div>
              <button type="button" class="mg-btn sm ghost shrink-0" phx-click="clear_focus">drop</button>
            </div>

            <%!-- one card per section, so two sections plainly look like two --%>
            <div class="mt-2 flex gap-2 flex-wrap">
              <div :for={sec <- @focus.sections} class="mg-held">
                <span class="n">{sec.ordinal}</span>
                <span class="min-w-0">
                  <span class="t">{sec.title}</span>
                  <span class="mg-meta">{sec.word_count} words, in full</span>
                </span>
              </div>
            </div>
          </div>

          <div :if={@cited != []} class="flex flex-col gap-1.5 mb-2.5">
            <div class="mg-label">
              Carrying {length(@cited)} passage{if length(@cited) > 1, do: "s"}
            </div>
            <div :for={{c, i} <- Enum.with_index(@cited)} class="mg-chip">
              <span class="min-w-0">
                <span class="cited">"{c.text}"</span>
                <span class="mg-meta">section {c.ordinal}</span>
              </span>
              <button type="button" class="x" phx-click="drop_context" phx-value-i={i} title="Drop">×</button>
            </div>
          </div>

          <form phx-submit="send" id="chat-form" phx-hook=".Composer" class="flex flex-col gap-2">
            <textarea
              name="message"
              rows="5"
              autocomplete="off"
              placeholder="Ask it something. Paste a paragraph you're stuck on, or a question you can't answer yourself."
              class="w-full text-[0.84rem] leading-relaxed resize-none min-h-[7.5rem] max-h-[22rem] px-3 py-2.5 bg-[var(--mg-card)] border border-[var(--mg-rule)] rounded-sm focus:outline-none focus:border-[var(--mg-accent)]"
              disabled={@loading}
            ></textarea>
            <div class="flex items-center gap-3">
              <span class="mg-hint mt-0">
                Enter to send · Shift+Enter for a new line<%= if is_integer(@quota) and @quota <= 20 do %>
                  · <span class="text-[var(--mg-accent)]">{@quota} left</span>
                <% end %>
              </span>
              <button
                type="submit"
                class="mg-btn ml-auto"
                disabled={@loading}
              >{if @loading, do: "Thinking…", else: "Ask"}</button>
            </div>
          </form>
        </div>
      <% end %>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".StickToBottom">
        // Follow the conversation only while the reader is already at the
        // bottom. Yanking someone back down mid-scroll while they are reading
        // an earlier answer is the single most irritating thing a chat can do.
        export default {
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
        };
      </script>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".Composer">
        // Enter sends, Shift+Enter writes a newline, and the box grows with
        // the question instead of hiding it one line at a time.
        export default {
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
        };
      </script>
    </div>
    """
  end
end
