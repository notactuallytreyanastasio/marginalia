defmodule MarginaliaWeb.StackLive.New do
  @moduledoc """
  Importing a stack of pull requests, from the page.

  The token is typed here, used for the fetch, and never written down. It is
  the reader's own credential and the only thing this does with it is `GET`;
  a token at rest in a database is a liability nobody asked this app to hold.
  """
  use MarginaliaWeb, :live_view

  alias Marginalia.Import.GitHub

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Import a stack",
       repo: "",
       token: "",
       folder: "",
       state: "open",
       working: false,
       progress: nil,
       error: nil
     )}
  end

  @impl true
  def handle_event("form", params, socket) do
    {:noreply,
     assign(socket,
       repo: params["repo"] || "",
       folder: params["folder"] || "",
       state: params["state"] || "open",
       error: nil
     )}
  end

  def handle_event("import", params, socket) do
    user_id = socket.assigns.current_scope.user.id
    repo = String.trim(params["repo"] || "")
    token = String.trim(params["token"] || "")
    folder = String.trim(params["folder"] || "")
    lv = self()

    case String.split(repo, "/", parts: 2) do
      [owner, name] when owner != "" and name != "" ->
        {:noreply,
         socket
         |> assign(working: true, error: nil, progress: {0, nil}, repo: repo, folder: folder)
         |> start_async(:import, fn ->
           GitHub.import_stack(user_id, owner, name, token,
             folder: if(folder == "", do: nil, else: folder),
             state: params["state"] || "open",
             on_item: fn _item, total -> send(lv, {:imported, total}) end
           )
         end)}

      _ ->
        {:noreply, assign(socket, error: "Write the repository as owner/name.", repo: repo)}
    end
  end

  @impl true
  def handle_info({:imported, total}, socket) do
    {done, _} = socket.assigns.progress || {0, total}
    {:noreply, assign(socket, progress: {done + 1, total})}
  end

  @impl true
  def handle_async(:import, {:ok, {:ok, %{folder: folder, created: made, total: total}}}, socket) do
    note =
      if made == total,
        do: "Imported #{made} documents.",
        else: "#{made} new, #{total - made} already there."

    {:noreply,
     socket
     |> assign(working: false)
     |> put_flash(:info, note)
     |> push_navigate(to: ~p"/stacks/#{folder.id}")}
  end

  def handle_async(:import, {:ok, {:error, reason}}, socket) do
    {:noreply, assign(socket, working: false, progress: nil, error: GitHub.explain(reason))}
  end

  def handle_async(:import, {:exit, reason}, socket) do
    {:noreply,
     assign(socket, working: false, progress: nil, error: "The import crashed: #{inspect(reason)}")}
  end

  # ==========================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-xl px-6 py-10">
        <div class="mg-meta"><.link navigate={~p"/stacks"}>← every method</.link></div>
        <h1 style="font-family:var(--mg-serif)" class="mt-2 text-2xl font-semibold tracking-tight">
          Import a stack
        </h1>
        <p class="mg-meta mt-2 leading-relaxed">
          A stack is pull requests each based on the one before it, so the series reads in
          order. The order is taken from that chain, not from the numbers — and if the
          repository is not a stack, this says which pull requests break it rather than
          importing them in a guessed order.
        </p>

        <form phx-submit="import" phx-change="form" class="mt-6 space-y-4">
          <label class="mg-field">
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

          <label class="mg-field">
            <span class="mg-label">GitHub token</span>
            <input
              type="password"
              name="token"
              value=""
              autocomplete="off"
              placeholder="used for this fetch, never stored"
              class="mg-input"
            />
            <span class="mg-meta">
              Needs only read access to the repository. It is used for the request and
              thrown away.
            </span>
          </label>

          <label class="mg-field">
            <span class="mg-label">Folder name</span>
            <input
              type="text"
              name="folder"
              value={@folder}
              placeholder={if @repo == "", do: "defaults to owner/name", else: @repo}
              autocomplete="off"
              class="mg-input"
            />
          </label>

          <label class="mg-field">
            <span class="mg-label">Which pull requests</span>
            <select name="state" class="mg-select">
              <option value="open" selected={@state == "open"}>Open</option>
              <option value="all" selected={@state == "all"}>All, open and closed</option>
            </select>
          </label>

          <p :if={@error} class="cut-err">{@error}</p>

          <div class="flex items-center gap-3">
            <button class="mg-btn" type="submit" disabled={@working}>
              {if @working, do: "Importing…", else: "Import"}
            </button>
            <span :if={@working and @progress} class="mg-meta">
              {elem(@progress, 0)} document{if elem(@progress, 0) == 1, do: "", else: "s"} saved
            </span>
          </div>
        </form>

        <p class="mg-meta mt-8 leading-relaxed">
          If the repository is not a stack, or you only want some of it,
          <.link navigate={~p"/import"}>import in bulk</.link>
          instead: that lists the pull requests first and lets you pick, and asks nothing
          about the shape they are in.
        </p>

        <p class="mg-meta mt-4 leading-relaxed">
          Importing saves each pull request's description as a draft, in order, in a folder.
          Nothing is read yet — that is the next three buttons on the folder's page.
        </p>
      </div>
    </Layouts.app>
    """
  end
end
