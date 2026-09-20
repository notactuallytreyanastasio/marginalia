defmodule MarginaliaWeb.LinkedLive.Show do
  @moduledoc """
  One pair of drafts and what runs between them.

  Read-only, and the edges are the whole content: each one names a node in
  each draft, the direction, and why. Grouped by kind rather than listed
  flat, because "where these two argue" is a different question from "what
  one carries further" and a reader is usually asking one of them.
  """
  use MarginaliaWeb, :live_view

  alias Marginalia.Links

  @order ~w(tension answers pays_off develops requires echoes)

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Links.public_link(id) do
      nil ->
        {:ok, socket |> put_flash(:error, "No such pair.") |> push_navigate(to: ~p"/linked")}

      link ->
        edges = Links.edges(link)

        {:ok,
         assign(socket,
           page_title: "#{link.a_work.title} ↔ #{link.b_work.title}",
           page_description: "#{length(edges)} edges between two drafts.",
           page_robots: "index, follow",
           link: link,
           grouped: group(edges),
           total: length(edges)
         )}
    end
  end

  defp group(edges) do
    by_kind = Enum.group_by(edges, & &1.edge_type)

    (@order ++ (Map.keys(by_kind) -- @order))
    |> Enum.uniq()
    |> Enum.filter(&Map.has_key?(by_kind, &1))
    |> Enum.map(&{&1, by_kind[&1]})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="lx">
        <div class="mg-meta">
          <.link navigate={~p"/linked"}>← Linked drafts</.link>
        </div>

        <h1>{@link.a_work.title} ↔ {@link.b_work.title}</h1>
        <p class="lede">
          {@total} edges. Each names a part of one draft and a part of the other, and the
          direction is part of the claim.
        </p>

        <p class="mg-meta">
          <.link navigate={~p"/drafts/#{@link.a_work.slug}"}>{@link.a_work.title}</.link>
          · <.link navigate={~p"/drafts/#{@link.b_work.slug}"}>{@link.b_work.title}</.link>
        </p>

        <section :for={{kind, edges} <- @grouped} class="lk-group">
          <h2 class="mg-label">{String.replace(kind, "_", " ")} · {length(edges)}</h2>

          <div :for={e <- edges} class={"lk-edge " <> kind}>
            <div class="lk-ends">
              <span class="from">{e.from && e.from.title}</span>
              <span class="arrow">{String.replace(kind, "_", " ")} →</span>
              <span class="to">{e.to && e.to.title}</span>
            </div>
            <p :if={e.rationale} class="why">{e.rationale}</p>
            <blockquote :if={e.from && e.from.quote} class="lk-quote">{e.from.quote}</blockquote>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
