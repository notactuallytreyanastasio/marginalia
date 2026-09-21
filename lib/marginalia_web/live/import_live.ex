defmodule MarginaliaWeb.ImportLive do
  @moduledoc """
  Bringing in a pile of documents at once, in steps.

  The two existing doors each take one thing: `/works/new` is one draft, and
  `/stacks/new` is one repository that has to *be* a stack — a strict chain
  of pull requests, refused by name if it is not. Neither of them is the
  thing people actually have, which is forty pull requests they would like
  to pick fifteen of, or a directory of markdown files.

  ## Why it is a flow and not a form

  A form commits before it shows you anything. That is fine for one draft
  and wrong here: the expensive, irreversible half of a bulk import is
  creating sixty works, and the question that decides whether that is the
  right sixty — "which of these do I mean?" — cannot be answered until after
  the listing has been fetched. So the fetch and the import are separate
  steps with the choosing in between, and the listing step is cheap: one
  request, no bodies, no commits. Nothing is created until a list has been
  looked at.

  ## Choosing, three ways, all at once

  A GitHub search query, a title regex, and the checkboxes are not three
  modes. The query runs on GitHub and decides what is fetched; the regex
  filters what came back and sets the selection; the checkboxes are the last
  word. Each is a narrowing of the one before, so any combination works and
  none of them has to be right first time.

  ## The token

  Typed at the find step, held in this process's assigns for the import
  step, and never written to the database, never rendered back into the
  page, never logged. It is the reader's own credential and the only thing
  either step does with it is `GET`.
  """
  use MarginaliaWeb, :live_view

  alias Marginalia.Import.{Bulk, GitHub, Query}

  @max_files 40
  @max_pick 200

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Import documents",
       page_robots: "noindex, nofollow",
       step: :source,
       source: nil,
       repo: "",
       token: "",
       mode: "repo",
       state: "all",
       query: "",
       pattern: "",
       pattern_error: nil,
       how: "query",
       order: "oldest",
       candidates: [],
       shown: [],
       chosen: MapSet.new(),
       commits: true,
       files: true,
       number: false,
       folder: "",
       working: false,
       phase: nil,
       progress: {0, 0},
       missed: [],
       result: nil,
       error: nil
     )
     |> allow_upload(:docs,
       accept: ~w(.txt .md .markdown .text),
       max_entries: @max_files,
       max_file_size: 8_000_000,
       auto_upload: true
     )}
  end

  # The HTTP half, swappable, so the flow can be tested without a network or
  # a token. Everything else about this page is the flow, and the flow is the
  # part that breaks.
  defp api, do: Application.get_env(:marginalia, :github_api, GitHub)

  # ==========================================================================
  # moving between steps

  @impl true
  def handle_event("source", %{"to" => "github"}, socket) do
    {:noreply, assign(socket, source: :github, step: :find, error: nil)}
  end

  def handle_event("source", %{"to" => "files"}, socket) do
    {:noreply, assign(socket, source: :files, step: :files, error: nil)}
  end

  def handle_event("back", _params, socket) do
    step =
      case socket.assigns.step do
        :pick -> :find
        :find -> :source
        :files -> :source
        other -> other
      end

    {:noreply, assign(socket, step: step, error: nil)}
  end

  def handle_event("restart", _params, socket) do
    {:noreply,
     assign(socket,
       step: :source,
       source: nil,
       candidates: [],
       shown: [],
       chosen: MapSet.new(),
       pattern: "",
       pattern_error: nil,
       result: nil,
       missed: [],
       error: nil,
       progress: {0, 0}
     )}
  end

  # ==========================================================================
  # finding

  def handle_event("form", params, socket) do
    {:noreply,
     assign(socket,
       repo: params["repo"] || socket.assigns.repo,
       query: params["query"] || socket.assigns.query,
       mode: params["mode"] || socket.assigns.mode,
       state: params["state"] || socket.assigns.state,
       error: nil
     )}
  end

  def handle_event("find", params, socket) do
    token = String.trim(params["token"] || "")
    mode = params["mode"] || "repo"
    repo = String.trim(params["repo"] || "")
    query = String.trim(params["query"] || "")
    state = params["state"] || "all"
    finder = api()

    socket = assign(socket, repo: repo, query: query, mode: mode, state: state, token: token)

    case mode do
      "search" when query == "" ->
        {:noreply, assign(socket, error: "Write a search query first.")}

      "repo" ->
        case String.split(repo, "/", parts: 2) do
          [owner, name] when owner != "" and name != "" ->
            {:noreply,
             socket
             |> assign(working: true, phase: :finding, error: nil)
             |> start_async(:find, fn -> finder.list(owner, name, token, state: state) end)}

          _ ->
            {:noreply, assign(socket, error: "Write the repository as owner/name.")}
        end

      "search" ->
        {:noreply,
         socket
         |> assign(working: true, phase: :finding, error: nil)
         |> start_async(:find, fn -> finder.search(query, token) end)}
    end
  end

  # ==========================================================================
  # choosing

  def handle_event("pattern", params, socket) do
    how = params["how"] || socket.assigns.how
    {:noreply, socket |> assign(how: how) |> refilter(params["pattern"] || "")}
  end

  def handle_event("toggle", %{"key" => key}, socket) do
    chosen = socket.assigns.chosen

    chosen =
      if MapSet.member?(chosen, key),
        do: MapSet.delete(chosen, key),
        else: MapSet.put(chosen, key)

    {:noreply, assign(socket, chosen: chosen)}
  end

  def handle_event("all", _params, socket) do
    chosen = socket.assigns.shown |> Enum.map(&key/1) |> MapSet.new()
    {:noreply, assign(socket, chosen: MapSet.union(socket.assigns.chosen, chosen))}
  end

  def handle_event("none", _params, socket) do
    shown = socket.assigns.shown |> Enum.map(&key/1) |> MapSet.new()
    {:noreply, assign(socket, chosen: MapSet.difference(socket.assigns.chosen, shown))}
  end

  def handle_event("order", %{"order" => order}, socket) do
    {:noreply,
     socket
     |> assign(order: order, candidates: sorted(socket.assigns.candidates, order))
     |> refilter(socket.assigns.pattern)}
  end

  def handle_event("settings", params, socket) do
    {:noreply,
     assign(socket,
       folder: params["folder"] || socket.assigns.folder,
       commits: params["commits"] == "true",
       files: params["files"] == "true",
       number: params["number"] == "true"
     )}
  end

  # ==========================================================================
  # importing pull requests

  def handle_event("import", _params, socket) do
    picked = picked(socket.assigns)

    cond do
      picked == [] ->
        {:noreply, assign(socket, error: "Nothing is selected.")}

      length(picked) > @max_pick ->
        {:noreply,
         assign(socket,
           error:
             "That is #{length(picked)} pull requests, and the ceiling is #{@max_pick} in one go. " <>
               "Narrow it and run it again — importing twice into the same folder skips what is already there."
         )}

      true ->
        lv = self()
        user_id = socket.assigns.current_scope.user.id
        token = socket.assigns.token
        commits = socket.assigns.commits
        files = socket.assigns.files
        finder = api()

        opts = [
          folder: socket.assigns.folder,
          number: socket.assigns.number
        ]

        {:noreply,
         socket
         |> assign(
           step: :running,
           working: true,
           phase: :fetching,
           error: nil,
           progress: {0, length(picked)}
         )
         |> start_async(:import, fn ->
           %{documents: docs, failed: failed} =
             finder.documents(picked, token,
               commits: commits,
               files: files,
               on_item: fn _c, total -> send(lv, {:tick, :fetching, total}) end
             )

           send(lv, {:phase, :landing, length(docs)})

           landed =
             Bulk.land(
               user_id,
               docs,
               Keyword.put(opts, :on_item, fn _t, _i, total ->
                 send(lv, {:tick, :landing, total})
               end)
             )

           {landed, failed}
         end)}
    end
  end

  # ==========================================================================
  # importing files

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("drop_file", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :docs, ref)}
  end

  def handle_event("import_files", params, socket) do
    folder = String.trim(params["folder"] || "")
    number = params["number"] == "true"
    user_id = socket.assigns.current_scope.user.id

    docs =
      consume_uploaded_entries(socket, :docs, fn %{path: path}, entry ->
        {:ok,
         %{
           title: Path.rootname(entry.client_name),
           body: File.read!(path),
           source_url: nil
         }}
      end)

    if docs == [] do
      {:noreply, assign(socket, error: "No files yet — drop some in.")}
    else
      lv = self()

      {:noreply,
       socket
       |> assign(
         step: :running,
         working: true,
         phase: :landing,
         error: nil,
         folder: folder,
         number: number,
         progress: {0, length(docs)}
       )
       |> start_async(:import, fn ->
         landed =
           Bulk.land(user_id, docs,
             folder: folder,
             number: number,
             on_item: fn _t, _i, total -> send(lv, {:tick, :landing, total}) end
           )

         {landed, []}
       end)}
    end
  end

  # ==========================================================================
  # progress

  @impl true
  def handle_info({:tick, phase, total}, socket) do
    {done, _} = socket.assigns.progress
    done = if socket.assigns.phase == phase, do: done + 1, else: 1
    {:noreply, assign(socket, phase: phase, progress: {done, total})}
  end

  def handle_info({:phase, phase, total}, socket) do
    {:noreply, assign(socket, phase: phase, progress: {0, total})}
  end

  @impl true
  def handle_async(:find, {:ok, {:ok, []}}, socket) do
    {:noreply, assign(socket, working: false, phase: nil, error: "Nothing matched.")}
  end

  def handle_async(:find, {:ok, {:ok, candidates}}, socket) do
    {:noreply,
     socket
     |> assign(
       working: false,
       phase: nil,
       step: :pick,
       candidates: sorted(candidates, socket.assigns.order),
       folder: default_folder(socket.assigns)
     )
     |> refilter(socket.assigns.pattern)}
  end

  def handle_async(:find, {:ok, {:error, reason}}, socket) do
    {:noreply, assign(socket, working: false, phase: nil, error: GitHub.explain(reason))}
  end

  def handle_async(:find, {:exit, reason}, socket) do
    {:noreply,
     assign(socket, working: false, phase: nil, error: "The search crashed: #{inspect(reason)}")}
  end

  def handle_async(:import, {:ok, {landed, missed}}, socket) do
    {:noreply,
     assign(socket,
       step: :done,
       working: false,
       phase: nil,
       result: landed,
       missed: missed
     )}
  end

  def handle_async(:import, {:exit, reason}, socket) do
    {:noreply,
     assign(socket,
       step: :done,
       working: false,
       phase: nil,
       error: "The import crashed: #{inspect(reason)}"
     )}
  end

  # ==========================================================================
  # the pieces the page is built from

  @doc false
  def key(%{repo: repo, number: number}), do: "#{repo}##{number}"

  defp picked(%{candidates: candidates, chosen: chosen}),
    do: Enum.filter(candidates, &MapSet.member?(chosen, key(&1)))

  # The filter is on the view *and* the selection, which is the answer to
  # "select these fifteen". Anything ticked by hand afterwards still counts:
  # the boxes are the last word, this just saves forty clicks getting to
  # them.
  #
  # Two languages, because they answer different questions. A query says
  # which pull requests these are — closed, last month, not from dependabot.
  # A regex says what the titles look like, which is the only way to catch a
  # numbering convention or a prefix nobody made a label for.
  defp refilter(socket, pattern) do
    narrow =
      case socket.assigns.how do
        "regex" -> Bulk.by_title(socket.assigns.candidates, pattern)
        _query -> Query.filter(socket.assigns.candidates, pattern)
      end

    case narrow do
      {:ok, shown} ->
        assign(socket,
          pattern: pattern,
          pattern_error: nil,
          shown: shown,
          chosen: shown |> Enum.map(&key/1) |> MapSet.new()
        )

      {:error, why} ->
        # keep the last good list on screen: a half-typed pattern should not
        # empty the page you are reading
        assign(socket, pattern: pattern, pattern_error: why)
    end
  end

  # Oldest first unless somebody says otherwise: see GitHub.oldest_first/1 for
  # why this is the order of the *documents* and not of a table.
  defp sorted(candidates, "newest"), do: candidates |> GitHub.oldest_first() |> Enum.reverse()
  defp sorted(candidates, _oldest), do: GitHub.oldest_first(candidates)

  defp default_folder(%{mode: "repo", repo: repo}) when repo != "", do: repo

  defp default_folder(%{query: query}) when query != "",
    do: "Search: #{String.slice(query, 0, 60)}"

  defp default_folder(_), do: "Imported"

  defp count(1, one, _many), do: "1 #{one}"
  defp count(n, _one, many), do: "#{n} #{many}"

  defp upload_error(:too_large), do: "over 8 MB"
  defp upload_error(:not_accepted), do: "not a text or markdown file"
  defp upload_error(:too_many_files), do: "more than #{max_files()} files"
  defp upload_error(other), do: to_string(other)

  # ==========================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-3xl px-6 py-10">
        <div class="mg-meta"><.link navigate={~p"/works"}>← every draft</.link></div>

        <h1 style="font-family:var(--mg-serif)" class="mt-2 text-2xl font-semibold tracking-tight">
          Import documents
        </h1>

        <ol class="im-steps">
          <li class={step_class(@step, [:source])}><span>1</span> Source</li>
          <li class={step_class(@step, [:find, :files])}><span>2</span> Find</li>
          <li class={step_class(@step, [:pick])}><span>3</span> Choose</li>
          <li class={step_class(@step, [:running, :done])}><span>4</span> Import</li>
        </ol>

        <p :if={@error} class="cut-err mt-4">{@error}</p>

        <%= case @step do %>
          <% :source -> %>
            <p class="mg-meta mt-4 leading-relaxed">
              Both of these land in a folder and stop. Nothing is read, and nothing costs
              anything, until you press the buttons on the folder afterwards.
            </p>

            <div class="im-pick">
              <button class="im-card" phx-click="source" phx-value-to="github">
                <span class="mg-label">GitHub</span>
                <b>Pull requests</b>
                <span>
                  A repository, or a search across several. Filter by title, tick the ones you
                  mean. Each becomes a draft of its description and its commit trail.
                </span>
              </button>

              <button class="im-card" phx-click="source" phx-value-to="files">
                <span class="mg-label">Files</span>
                <b>From this computer</b>
                <span>
                  Up to {max_files()} markdown or text files, dropped together. Each one becomes
                  a draft, named after the file.
                </span>
              </button>
            </div>
          <% :find -> %>
            <form id="im-find" phx-submit="find" phx-change="form" class="mt-6 space-y-4">
              <div class="im-modes">
                <label class={["im-mode", @mode == "repo" && "on"]}>
                  <input type="radio" name="mode" value="repo" checked={@mode == "repo"} />
                  <b>One repository</b>
                  <span>Every pull request in it, then filter.</span>
                </label>
                <label class={["im-mode", @mode == "search" && "on"]}>
                  <input type="radio" name="mode" value="search" checked={@mode == "search"} />
                  <b>A search</b>
                  <span>GitHub's own query language, across repositories.</span>
                </label>
              </div>

              <label :if={@mode == "repo"} class="mg-field">
                <span class="mg-label">Repository</span>
                <input
                  type="text"
                  name="repo"
                  value={@repo}
                  placeholder="owner/name"
                  autocomplete="off"
                  class="mg-input"
                />
              </label>

              <label :if={@mode == "repo"} class="mg-field">
                <span class="mg-label">Which pull requests</span>
                <select name="state" class="mg-select">
                  <option value="all" selected={@state == "all"}>All, open and closed</option>
                  <option value="open" selected={@state == "open"}>Open only</option>
                  <option value="closed" selected={@state == "closed"}>Closed only</option>
                </select>
              </label>

              <label :if={@mode == "search"} class="mg-field">
                <span class="mg-label">Search</span>
                <input
                  type="text"
                  name="query"
                  value={@query}
                  placeholder="repo:owner/name label:design merged:>2025-01-01"
                  autocomplete="off"
                  class="mg-input"
                />
                <span class="mg-meta">
                  Passed to GitHub as written; <code>is:pr</code>
                  is added for you. Search is capped at 1000 results and rate limited to
                  30 a minute, both by GitHub.
                </span>
              </label>

              <label class="mg-field">
                <span class="mg-label">GitHub token <em>optional</em></span>
                <input
                  type="password"
                  name="token"
                  value=""
                  autocomplete="off"
                  placeholder="leave blank for a public repository"
                  class="mg-input"
                />
                <span class="mg-meta">
                  A public repository needs none, at 60 requests an hour and 10 searches a
                  minute. A token raises that to 5000 an hour and reaches private
                  repositories; read access is enough. It is held for as long as this page is
                  open and written down nowhere.
                </span>
              </label>

              <div class="flex items-center gap-3">
                <button class="mg-btn" type="submit" disabled={@working}>
                  {if @working, do: "Looking…", else: "Find them"}
                </button>
                <button class="mg-btn sm ghost" type="button" phx-click="back">back</button>
              </div>
            </form>
          <% :pick -> %>
            <form id="im-pattern" phx-change="pattern" class="mt-6">
              <span class="mg-label">Narrow this list</span>

              <div class="im-filter">
                <select name="how" class="mg-select sm">
                  <option value="query" selected={@how == "query"}>Query</option>
                  <option value="regex" selected={@how == "regex"}>Title regex</option>
                </select>
                <input
                  type="text"
                  name="pattern"
                  value={@pattern}
                  placeholder={
                    if @how == "regex",
                      do: "a regular expression — ^\d+\. or fix|revert",
                      else: "is:pr state:closed created:>@today-30d"
                  }
                  autocomplete="off"
                  class="mg-input"
                  phx-debounce="300"
                />
              </div>

              <p :if={@pattern_error} class="cut-err mt-2">{@pattern_error}</p>

              <p :if={!@pattern_error and @how == "regex"} class="mg-meta mt-2">
                Case insensitive, matched against the title. Filters the list and selects what
                it matches — the boxes below still have the last word.
              </p>

              <p :if={!@pattern_error and @how != "regex"} class="mg-meta mt-2">
                Runs over the rows already fetched, so it costs nothing and does not have to be
                right first time. <code>state:</code>
                <code>is:</code>
                <code>draft:</code>
                <code>repo:</code>
                <code>base:</code>
                <code>head:</code>
                <code>number:</code>, the dates <code>created:</code>
                <code>updated:</code>
                <code>merged:</code>, and a bare word matches the title. Dates take
                <code>@today-30d</code>
                as well as <code>2025-08-05</code>, and <code>-</code>
                in front of anything takes it away.
              </p>
            </form>

            <form id="im-order" phx-change="order" class="im-order">
              <span class="mg-label">Order</span>
              <select name="order" class="mg-select sm">
                <option value="oldest" selected={@order == "oldest"}>
                  Oldest first, by when it landed
                </option>
                <option value="newest" selected={@order == "newest"}>Newest first</option>
              </select>
              <span class="mg-meta">
                This is the order they are created in, and the order the folder is read
                forwards in. For a release, oldest first.
              </span>
            </form>

            <div class="im-bar">
              <span>
                {count(length(@shown), "pull request", "pull requests")} shown{if length(@shown) !=
                                                                                    length(
                                                                                      @candidates
                                                                                    ),
                                                                                  do:
                                                                                    " of #{length(@candidates)}"} ·
                <b>{MapSet.size(@chosen)} selected</b>
              </span>
              <button class="mg-btn sm ghost" type="button" phx-click="all">select all shown</button>
              <button class="mg-btn sm ghost" type="button" phx-click="none">clear shown</button>
            </div>

            <ul class="im-list">
              <li :for={c <- @shown} class={["im-row", MapSet.member?(@chosen, key(c)) && "on"]}>
                <label>
                  <input
                    type="checkbox"
                    checked={MapSet.member?(@chosen, key(c))}
                    phx-click="toggle"
                    phx-value-key={key(c)}
                  />
                  <span class="n">#{c.number}</span>
                  <span class="t">{c.title}</span>
                  <span :if={c.merged_at} class="d">{String.slice(c.merged_at, 0, 10)}</span>
                  <span class={["s", c.state]}>{c.state}</span>
                  <span :if={c.draft} class="s draft">draft</span>
                  <span class="r">{c.repo}</span>
                </label>
              </li>
            </ul>

            <p :if={@shown == []} class="mg-meta mt-3">
              Nothing matches that pattern.
            </p>

            <form id="im-settings" phx-submit="import" phx-change="settings" class="mt-6 space-y-4">
              <label class="mg-field">
                <span class="mg-label">Folder</span>
                <input
                  type="text"
                  name="folder"
                  value={@folder}
                  placeholder="left empty, they go in loose"
                  autocomplete="off"
                  class="mg-input"
                />
              </label>

              <label class="im-check">
                <input type="hidden" name="commits" value="false" />
                <input type="checkbox" name="commits" value="true" checked={@commits} />
                <span>
                  <b>Include the commit trail.</b>
                  The description argues; the commits are what was done. One more request each.
                </span>
              </label>

              <label class="im-check">
                <input type="hidden" name="files" value="false" />
                <input type="checkbox" name="files" value="true" checked={@files} />
                <span>
                  <b>Include the files changed.</b>
                  Paths and line counts, not diffs — what the change is about, in one glance.
                  One more request each.
                </span>
              </label>

              <label class="im-check">
                <input type="hidden" name="number" value="false" />
                <input type="checkbox" name="number" value="true" checked={@number} />
                <span>
                  <b>Number the titles.</b>
                  Only if these are a series meant to be read in order — that is where the
                  stack reader looks for the order.
                </span>
              </label>

              <div class="flex items-center gap-3">
                <button class="mg-btn" type="submit" disabled={MapSet.size(@chosen) == 0}>
                  Import {MapSet.size(@chosen)}
                </button>
                <button class="mg-btn sm ghost" type="button" phx-click="back">back</button>
              </div>
            </form>
          <% :files -> %>
            <form id="im-files" phx-submit="import_files" phx-change="validate" class="mt-6 space-y-4">
              <div class="im-drop" phx-drop-target={@uploads.docs.ref}>
                <p class="mg-meta">
                  Drop up to {max_files()} markdown or text files here, or choose them. Each one
                  becomes a draft named after the file.
                </p>
                <.live_file_input upload={@uploads.docs} />
              </div>

              <p :for={err <- upload_errors(@uploads.docs)} class="cut-err">
                {upload_error(err)}
              </p>

              <ul :if={@uploads.docs.entries != []} class="im-list">
                <li :for={entry <- @uploads.docs.entries} class="im-row on">
                  <span class="t">{entry.client_name}</span>
                  <span class="s">{entry.progress}%</span>
                  <span :for={err <- upload_errors(@uploads.docs, entry)} class="cut-err">
                    {upload_error(err)}
                  </span>
                  <button
                    type="button"
                    class="mg-btn sm ghost"
                    phx-click="drop_file"
                    phx-value-ref={entry.ref}
                  >
                    remove
                  </button>
                </li>
              </ul>

              <label class="mg-field">
                <span class="mg-label">Folder</span>
                <input
                  type="text"
                  name="folder"
                  value={@folder}
                  placeholder="left empty, they go in loose"
                  autocomplete="off"
                  class="mg-input"
                />
              </label>

              <label class="im-check">
                <input type="hidden" name="number" value="false" />
                <input type="checkbox" name="number" value="true" checked={@number} />
                <span>
                  <b>Number the titles.</b> Only if these are a series meant to be read in order.
                </span>
              </label>

              <div class="flex items-center gap-3">
                <button class="mg-btn" type="submit" disabled={@uploads.docs.entries == []}>
                  Import {length(@uploads.docs.entries)}
                </button>
                <button class="mg-btn sm ghost" type="button" phx-click="back">back</button>
              </div>
            </form>
          <% :running -> %>
            <div class="mt-8">
              <p class="mg-label">
                {if @phase == :fetching, do: "Reading them off GitHub", else: "Filing them"}
              </p>
              <div class="im-progress">
                <span style={"width:#{percent(@progress)}%"}></span>
              </div>
              <p class="mg-meta mt-2">
                {elem(@progress, 0)} of {elem(@progress, 1)}
              </p>
              <p class="mg-meta mt-6 leading-relaxed">
                Leave this page open. Fetching is six at a time and filing is one at a time,
                which is slower and is the half that writes to the database.
              </p>
            </div>
          <% :done -> %>
            <div :if={@result} class="mt-8">
              <p style="font-family:var(--mg-serif)" class="text-xl font-semibold">
                {count(length(@result.created), "draft", "drafts")} imported.
              </p>

              <p :if={@result.skipped != []} class="mg-meta mt-2">
                {count(length(@result.skipped), "was", "were")} already in the folder under the
                same title and {if length(@result.skipped) == 1, do: "was", else: "were"} left alone.
              </p>

              <div :if={@result.failed != []} class="mt-4">
                <p class="mg-label">Not imported</p>
                <ul class="im-bad">
                  <li :for={{title, reason} <- @result.failed}>
                    {title} — {Bulk.explain(reason)}
                  </li>
                </ul>
              </div>

              <div :if={@missed != []} class="mt-4">
                <p class="mg-label">Could not be fetched</p>
                <ul class="im-bad">
                  <li :for={{c, reason} <- @missed}>
                    #{c.number} {c.title} — {GitHub.explain(reason)}
                  </li>
                </ul>
              </div>

              <div class="mt-6 flex items-center gap-3">
                <.link
                  :if={@result.folder}
                  navigate={~p"/stacks/#{@result.folder.id}"}
                  class="mg-btn"
                >
                  Open the folder
                </.link>
                <.link :if={is_nil(@result.folder)} navigate={~p"/works"} class="mg-btn">
                  Every draft
                </.link>
                <button class="mg-btn sm ghost" type="button" phx-click="restart">
                  import some more
                </button>
              </div>
            </div>

            <div :if={is_nil(@result)} class="mt-8">
              <button class="mg-btn" type="button" phx-click="restart">start again</button>
            </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  # Inside ~H, `@max_files` is an *assign* — the module attribute is
  # invisible there, and reading it raises KeyError at render, which in a
  # LiveView means a dropped socket rather than an error page.
  defp max_files, do: @max_files

  defp step_class(step, steps), do: ["im-step", step in steps && "on"]

  defp percent({_done, 0}), do: 0
  defp percent({done, total}), do: round(done / total * 100)
end
