defmodule MarginaliaWeb.DraftLive.Index do
  @moduledoc """
  Every draft on the public face of this deploy.

  The owner's own work, listed and indexable. Nobody else's drafts appear
  here: a visitor who uploads something still has exactly what they always
  had, a private link, and this page is the owner publishing themselves.
  """
  use MarginaliaWeb, :live_view

  alias Marginalia.Works

  @impl true
  def mount(_params, _session, socket) do
    drafts = Works.public_drafts()

    {:ok,
     assign(socket,
       page_title: "Drafts",
       page_description: "Drafts read end to end, with the notes that came out of reading them.",
       page_robots: "index, follow",
       drafts: drafts,
       total: length(drafts)
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="lx">
        <h1>Drafts</h1>
        <p class="lede">
          {@total} drafts, read end to end. Each one carries the notes that came out of
          reading it, in the margin beside the sentence that caused them.
        </p>

        <p :if={@drafts == []} class="mg-empty">Nothing here yet.</p>

        <ul class="mg-rows">
          <li :for={d <- @drafts}>
            <.link navigate={~p"/drafts/#{d.slug}"} class="t">{d.title}</.link>
            <p class="mg-meta">
              {d.word_count} words · {d.status}
            </p>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end
end
