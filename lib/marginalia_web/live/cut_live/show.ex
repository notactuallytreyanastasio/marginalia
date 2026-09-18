defmodule MarginaliaWeb.CutLive.Show do
  @moduledoc """
  What a cut turned out to say.

  The reading is kicked off here rather than on the page that made the cut, so
  the reader lands on the thing they asked for while it is still being written
  instead of watching a spinner on a form they have finished with.
  """
  use MarginaliaWeb, :live_view

  alias Marginalia.Cuts

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Cuts.get_cut(user_id, id) do
      nil ->
        {:ok, socket |> put_flash(:error, "No such cut.") |> push_navigate(to: ~p"/cuts")}

      cut ->
        socket = assign(socket, page_title: cut.title, cut: cut)
        {:ok, if(cut.status == "draft", do: start_read(socket), else: socket)}
    end
  end

  defp start_read(socket) do
    cut = socket.assigns.cut
    {:ok, cut} = Cuts.set_status(cut, "reading")

    socket
    |> assign(cut: %{cut | picks: socket.assigns.cut.picks})
    |> start_async(:read, fn -> Cuts.read(cut) end)
  end

  @impl true
  def handle_async(:read, {:ok, {:ok, _updated}}, socket) do
    user_id = socket.assigns.current_scope.user.id
    {:noreply, assign(socket, cut: Cuts.get_cut(user_id, socket.assigns.cut.id))}
  end

  def handle_async(:read, {:ok, other}, socket) do
    user_id = socket.assigns.current_scope.user.id

    {:noreply,
     socket
     |> assign(cut: Cuts.get_cut(user_id, socket.assigns.cut.id))
     |> put_flash(:error, "The read did not finish: #{inspect(other)}")}
  end

  def handle_async(:read, {:exit, reason}, socket) do
    {:ok, cut} = Cuts.set_status(socket.assigns.cut, "failed", inspect(reason))
    {:noreply, socket |> assign(cut: cut) |> put_flash(:error, "The read crashed.")}
  end

  @impl true
  def handle_event("again", _params, socket), do: {:noreply, start_read(socket)}

  def handle_event("delete", _params, socket) do
    {:ok, _} = Cuts.delete_cut(socket.assigns.cut)
    {:noreply, socket |> put_flash(:info, "Cut deleted.") |> push_navigate(to: ~p"/cuts")}
  end

  # ==========================================================================

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns, works: Cuts.works(assigns.cut), stale: not Cuts.current?(assigns.cut))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-3xl px-6 py-10">
        <div class="mg-meta"><.link navigate={~p"/cuts"}>← every cut</.link></div>
        <h1 style="font-family:var(--mg-serif)" class="mt-2 text-2xl font-semibold tracking-tight">
          {@cut.title}
        </h1>
        <p :if={@cut.question && @cut.question != ""} class="cut-ask">{@cut.question}</p>
        <div class="mg-meta mt-2">
          {length(@cut.picks)} passages across {length(@works)} drafts
        </div>
        <ul class="cut-works">
          <li :for={w <- @works}>
            <.link navigate={~p"/works/#{w.slug}"}>{w.title}</.link>
          </li>
        </ul>

        <%= case @cut.status do %>
          <% "reading" -> %>
            <p class="cut-working">
              Reading these passages together. One call, and it is the slow kind.
            </p>
          <% "failed" -> %>
            <p class="cut-err mt-6">
              The read failed. {@cut.status_detail}
              <button class="mg-btn sm ghost ml-2" phx-click="again">try again</button>
            </p>
          <% "read" -> %>
            <p :if={@stale} class="cut-stale">
              These passages have changed since this was read.
              <button class="mg-btn sm ghost ml-2" phx-click="again">read again</button>
            </p>

            <h2 class="cut-h">Thesis</h2>
            <p class="cut-thesis">{@cut.thesis}</p>

            <.group title="Through-lines" items={@cut.threads} works={@works} />
            <.group title="Tensions" items={@cut.tensions} works={@works} />

            <div :if={@cut.not_supported not in [nil, ""]}>
              <h2 class="cut-h">What this does not show</h2>
              <p class="cut-body">{@cut.not_supported}</p>
            </div>
          <% _ -> %>
            <p class="cut-working">Queued.</p>
        <% end %>

        <h2 class="cut-h">The passages</h2>
        <div :for={p <- @cut.picks} class="cut-src">
          <div class="mg-label">{p.work.title} · {p.block_ref}</div>
          <p>{p.quote}</p>
        </div>

        <div class="mt-8 flex gap-2 border-t border-[var(--mg-rule)] pt-4">
          <button :if={@cut.status == "read"} class="mg-btn sm ghost" phx-click="again">
            read again
          </button>
          <span :if={@cut.dropped != []} class="mg-meta self-center">
            {length(@cut.dropped)} claim{if length(@cut.dropped) == 1, do: "", else: "s"} dropped
            for quotes that could not be found
          </span>
          <button
            class="mg-btn sm ghost ml-auto"
            phx-click="delete"
            data-confirm="Delete this cut and its reading?"
          >delete</button>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :title, :string, required: true
  attr :items, :list, required: true
  attr :works, :list, required: true

  defp group(assigns) do
    ~H"""
    <div :if={@items != []}>
      <h2 class="cut-h">{@title}</h2>
      <div :for={item <- @items} class="cut-claim">
        <p class="c">{item["claim"]}</p>
        <blockquote :for={ev <- item["evidence"] || []}>
          {ev["quote"]}
          <cite>{title_for(@works, ev)}</cite>
        </blockquote>
      </div>
    </div>
    """
  end

  defp title_for(works, %{"work_id" => id}) when is_integer(id) do
    case Enum.find(works, &(&1.id == id)) do
      nil -> "a draft in this cut"
      w -> w.title
    end
  end

  defp title_for(_works, ev), do: "document #{ev["document"]}"
end
