defmodule MarginaliaWeb.StackLive.Index do
  @moduledoc "Folders that can be read forwards, as the method they embody."
  use MarginaliaWeb, :live_view

  alias Marginalia.{Folders, Stacks}

  @impl true
  def mount(_params, _session, socket), do: {:ok, load(assign(socket, page_title: "Methods"))}

  defp load(socket) do
    user_id = socket.assigns.current_scope.user.id

    rows =
      user_id
      |> Folders.tree()
      |> flatten(0)
      |> Enum.map(fn {folder, depth} ->
        %{folder: folder, depth: depth, stats: Stacks.stats(user_id, folder.id)}
      end)
      |> Enum.filter(&(&1.stats.documents > 0))

    assign(socket, rows: rows)
  end

  defp flatten(node, depth) do
    Enum.flat_map(node.folders, fn f -> [{f.folder, depth} | flatten(f, depth + 1)] end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-3xl px-6 py-10">
        <div class="flex items-baseline gap-3 border-b border-[var(--mg-rule)] pb-4">
          <h1 style="font-family:var(--mg-serif)" class="text-2xl font-semibold tracking-tight">
            Methods
          </h1>
          <span class="mg-meta">{length(@rows)} readable folders</span>
          <.link navigate={~p"/import"} class="mg-btn sm ghost ml-auto">Import many</.link>
          <.link navigate={~p"/stacks/new"} class="mg-btn sm">Import a stack</.link>
        </div>

        <p class="mg-meta mt-4 leading-relaxed">
          A folder of documents that build one thing, read <em>forwards</em>: each document told
          only what the ones before it established. What comes back is what somebody building
          the same thing would have to do, in order.
        </p>

        <p :if={@rows == []} class="mg-empty mt-8">
          Nothing here yet. Put some drafts in a folder and it becomes readable.
        </p>

        <div class="mg-rows mt-2">
          <div :for={r <- @rows} class="cut-row" style={"padding-left:#{r.depth * 1.4}rem"}>
            <div class="min-w-0 flex-1">
              <.link
                navigate={~p"/stacks/#{r.folder.id}"}
                style="font-family:var(--mg-serif)"
                class="text-[1.05rem] hover:text-[var(--mg-accent)]"
              >{r.folder.name}</.link>
              <div class="mg-meta mt-0.5">
                {r.stats.documents} documents
                <span :if={r.stats.read > 0}>· {r.stats.read} read</span>
                <span :if={r.stats.pitfalls > 0}>· {r.stats.pitfalls} pitfalls</span>
                <span :if={r.stats.stale > 0} class="cut-err">· {r.stats.stale} stale</span>
              </div>
            </div>
            <span :if={r.stats.read == r.stats.documents} class="mg-badge ink">read</span>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
