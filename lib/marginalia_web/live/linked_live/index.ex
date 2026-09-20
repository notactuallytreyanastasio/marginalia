defmodule MarginaliaWeb.LinkedLive.Index do
  @moduledoc """
  Pairs of the owner's drafts that were read against each other and found
  something.

  Only the ones with edges. A pass that ran and reported nothing is a real
  answer, and it is on the writer's own page; a public index of empty
  comparisons is an index of nothing.
  """
  use MarginaliaWeb, :live_view

  alias Marginalia.Links

  @impl true
  def mount(_params, _session, socket) do
    links = Links.public_links()

    {:ok,
     assign(socket,
       page_title: "Linked drafts",
       page_description:
         "Pairs of drafts read against each other, with the edges between them: what develops what, what pays off what, and where they argue.",
       page_robots: "index, follow",
       links: links,
       counts: Map.new(links, &{&1.id, Links.edge_count(&1.id)})
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="lx">
        <h1>Linked drafts</h1>
        <p class="lede">
          Two drafts read against each other, with every edge the pass found: what develops
          what, what pays off a promise the other made, and where the two argue. The
          direction is part of the claim.
        </p>

        <p :if={@links == []} class="mg-empty">Nothing linked yet.</p>

        <ul class="mg-rows">
          <li :for={l <- @links}>
            <.link navigate={~p"/linked/#{l.id}"} class="t">
              {l.a_work.title} ↔ {l.b_work.title}
            </.link>
            <p class="mg-meta">{@counts[l.id]} edges</p>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end
end
