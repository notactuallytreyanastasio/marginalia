defmodule MarginaliaWeb.WorkLive.Index do
  @moduledoc "A writer's drafts."
  use MarginaliaWeb, :live_view

  alias Marginalia.Works

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Your drafts",
       works: Works.list_works(socket.assigns.current_scope.user.id)
     )}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Works.get_work(user_id, id) do
      nil -> {:noreply, socket}
      work ->
        {:ok, _} = Works.delete_work(work)
        {:noreply, assign(socket, works: Works.list_works(user_id)) |> put_flash(:info, "Deleted.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-4xl px-6 py-10">
        <div class="flex items-baseline gap-3 border-b border-[var(--mg-rule)] pb-4">
          <h1 style="font-family:var(--mg-serif)" class="text-2xl font-semibold tracking-tight">
            Your drafts
          </h1>
          <span class="mg-meta">{length(@works)}</span>
          <.link navigate={~p"/works/new"} class="mg-btn ml-auto">Upload a draft</.link>
        </div>

        <%= if @works == [] do %>
          <p class="mg-empty mt-8">Nothing here yet. Bring the draft in the drawer.</p>
        <% else %>
          <div class="mg-rows mt-2">
            <%= for w <- @works do %>
              <div class="mg-row py-4">
                <div class="min-w-0 flex-1">
                  <.link
                    navigate={~p"/works/#{w.slug}"}
                    style="font-family:var(--mg-serif)"
                    class="text-[1.1rem] hover:text-[var(--mg-accent)]"
                  >{w.title}</.link>
                  <div class="mg-meta mt-0.5">{w.word_count} words</div>
                </div>
                <span class={"mg-badge " <> if(w.status == "read", do: "ink", else: "")}>{w.status}</span>
                <button
                  class="mg-btn sm ghost"
                  phx-click="delete"
                  phx-value-id={w.id}
                  data-confirm="Delete this draft, its map and its conversations?"
                >delete</button>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
