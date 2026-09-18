defmodule MarginaliaWeb.CutLive.Index do
  @moduledoc "Every line this writer has drawn through their drafts."
  use MarginaliaWeb, :live_view

  alias Marginalia.Cuts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Cuts",
       cuts: Cuts.list_cuts(socket.assigns.current_scope.user.id)
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-3xl px-6 py-10">
        <div class="flex items-baseline gap-3 border-b border-[var(--mg-rule)] pb-4">
          <h1 style="font-family:var(--mg-serif)" class="text-2xl font-semibold tracking-tight">
            Cuts
          </h1>
          <span class="mg-meta">{length(@cuts)}</span>
          <.link navigate={~p"/cuts/new"} class="mg-btn ml-auto">New cut</.link>
        </div>

        <p :if={@cuts == []} class="mg-empty mt-8">
          A cut is a line through several drafts: the passages you think belong together, read
          as one thing. Nothing here yet.
        </p>

        <div class="mg-rows mt-2">
          <div :for={c <- @cuts} class="mg-row py-4">
            <div class="min-w-0 flex-1">
              <.link
                navigate={~p"/cuts/#{c.id}"}
                style="font-family:var(--mg-serif)"
                class="text-[1.1rem] hover:text-[var(--mg-accent)]"
              >{c.title}</.link>
              <div class="mg-meta mt-0.5">
                {length(c.picks)} passages · {length(Cuts.works(c))} drafts
                <span :if={c.dropped != []}>· {length(c.dropped)} dropped</span>
              </div>
            </div>
            <span class={"mg-badge " <> if(c.status == "read", do: "ink", else: "")}>{c.status}</span>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
