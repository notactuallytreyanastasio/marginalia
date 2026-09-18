defmodule MarginaliaWeb.CutLive.Index do
  @moduledoc "Every folder this writer has had read, and the ones still waiting."
  use MarginaliaWeb, :live_view

  alias Marginalia.{Cuts, Folders}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load(assign(socket, page_title: "Readings"))}
  end

  defp load(socket) do
    user_id = socket.assigns.current_scope.user.id
    cuts = Cuts.list_cuts(user_id)
    by_folder = Map.new(cuts, &{&1.folder_id, &1})

    assign(socket,
      rows: rows(Folders.tree(user_id), by_folder, 0),
      count: length(cuts)
    )
  end

  # The folder tree, flattened, because the tree *is* the list of things that
  # can be read — and the order it is read in matters: a parent standing on
  # unread children is worth less than one standing on read ones.
  defp rows(node, by_folder, depth) do
    Enum.flat_map(node.folders, fn f ->
      [
        %{
          folder: f.folder,
          depth: depth,
          works: length(f.works),
          subfolders: length(f.folders),
          count: f.count,
          cut: Map.get(by_folder, f.folder.id)
        }
        | rows(f, by_folder, depth + 1)
      ]
    end)
  end

  @impl true
  def handle_event("read", %{"folder" => folder_id}, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Cuts.open_folder_reading(user_id, String.to_integer(folder_id)) do
      {:ok, cut} -> {:noreply, push_navigate(socket, to: ~p"/cuts/#{cut.id}")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "That folder is not yours.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-3xl px-6 py-10">
        <div class="flex items-baseline gap-3 border-b border-[var(--mg-rule)] pb-4">
          <h1 style="font-family:var(--mg-serif)" class="text-2xl font-semibold tracking-tight">
            Readings
          </h1>
          <span class="mg-meta">{@count} of {length(@rows)} folders read</span>
          <.link navigate={~p"/works"} class="mg-btn sm ghost ml-auto">Folders</.link>
        </div>

        <p :if={@rows == []} class="mg-empty mt-8">
          A reading is what a folder says that none of its drafts says alone. Make a folder
          on the drafts page and there will be something here to read.
        </p>

        <p :if={@rows != []} class="mg-meta mt-4 leading-relaxed">
          Read from the inside out. A folder of folders is read over what its children
          already found, so reading a case first makes the reading above it worth more.
        </p>

        <div class="mg-rows mt-2">
          <div :for={r <- @rows} class="cut-row" style={"padding-left:#{r.depth * 1.4}rem"}>
            <div class="min-w-0 flex-1">
              <span :if={r.cut} class="mg-badge ink mr-2">read</span>
              <.link
                :if={r.cut}
                navigate={~p"/cuts/#{r.cut.id}"}
                style="font-family:var(--mg-serif)"
                class="text-[1.05rem] hover:text-[var(--mg-accent)]"
              >{r.folder.name}</.link>
              <span
                :if={is_nil(r.cut)}
                style="font-family:var(--mg-serif)"
                class="text-[1.05rem] text-[var(--mg-dim)]"
              >{r.folder.name}</span>
              <div class="mg-meta mt-0.5">
                <%= if r.subfolders > 0 do %>
                  {r.subfolders} folders · {r.count} drafts below
                <% else %>
                  {r.works} drafts
                <% end %>
                <span :if={r.cut && r.cut.status == "read"}>
                  · {length(r.cut.threads)} through-lines
                </span>
                <span :if={r.cut && r.cut.status not in ["read", "draft"]}>· {r.cut.status}</span>
              </div>
            </div>
            <button class="mg-btn sm ghost" phx-click="read" phx-value-folder={r.folder.id}>
              {if r.cut, do: "read again", else: "read"}
            </button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
