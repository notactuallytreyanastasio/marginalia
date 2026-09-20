defmodule MarginaliaWeb.LinkedLive.Index do
  @moduledoc """
  Pairs of the owner's drafts that were read against each other and found
  something.

  Three hundred and ninety-two of them, which is more list than anyone
  scrolls. So the ones with a tension come first — two things the writer
  said that sit badly together is the finding worth the money, and burying
  those under three hundred pairs that merely develop each other is the
  wrong order. A filter narrows by title without a round trip, and the page
  hands over a screenful at a time rather than all of it at once.
  """
  use MarginaliaWeb, :live_view

  alias Marginalia.Links

  @page 40

  @impl true
  def mount(_params, _session, socket) do
    rows = Links.public_links()

    {:ok,
     assign(socket,
       page_title: "Linked drafts",
       page_description:
         "Pairs of drafts read against each other, with the edges between them: what develops what, what pays off what, and where they argue.",
       page_robots: "index, follow",
       rows: rows,
       total: length(rows),
       tensions: Enum.count(rows, &(&1.tensions > 0)),
       filter: "",
       limit: @page
     )}
  end

  @impl true
  def handle_event("filter", %{"q" => q}, socket),
    do: {:noreply, assign(socket, filter: q, limit: @page)}

  def handle_event("more", _params, socket),
    do: {:noreply, assign(socket, limit: socket.assigns.limit + @page)}

  defp matching(rows, ""), do: rows

  defp matching(rows, q) do
    needle = String.downcase(q)

    Enum.filter(rows, fn r ->
      String.contains?(String.downcase(r.link.a_work.title), needle) or
        String.contains?(String.downcase(r.link.b_work.title), needle)
    end)
  end

  @impl true
  def render(assigns) do
    found = matching(assigns.rows, assigns.filter)
    assigns = assign(assigns, found: found, shown: Enum.take(found, assigns.limit))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="lx">
        <h1>Linked drafts</h1>
        <p class="lede">
          Two drafts read against each other, with every edge the pass found: what develops
          what, what pays off a promise the other made, and where the two argue. The
          direction is part of the claim.
        </p>

        <p class="mg-meta">
          {@total} pairs · {@tensions} of them contain a tension, and those are first
        </p>

        <form phx-change="filter" id="lk-filter" class="lk-filter">
          <input
            type="text"
            name="q"
            value={@filter}
            placeholder="narrow by title — a case name, a chapter number"
            autocomplete="off"
          />
        </form>

        <p :if={@found == []} class="mg-empty">
          Nothing matches “{@filter}”.
        </p>

        <ul class="mg-rows">
          <li :for={r <- @shown} class={if r.tensions > 0, do: "has-tension", else: ""}>
            <.link navigate={~p"/linked/#{r.link.id}"} class="t">
              {r.link.a_work.title} ↔ {r.link.b_work.title}
            </.link>
            <p class="mg-meta">
              {r.edges} edges<span :if={r.tensions > 0} class="tension-count">
                · {r.tensions} tension{if r.tensions == 1, do: "", else: "s"}
              </span>
            </p>
          </li>
        </ul>

        <div :if={length(@found) > length(@shown)} class="lk-more">
          <button class="mg-btn sm" phx-click="more">
            Show {min(40, length(@found) - length(@shown))} more
            <span class="mg-meta">of {length(@found) - length(@shown)} left</span>
          </button>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
