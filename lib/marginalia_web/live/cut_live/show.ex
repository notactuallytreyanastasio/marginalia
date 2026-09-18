defmodule MarginaliaWeb.CutLive.Show do
  @moduledoc """
  What a folder turned out to say.

  The members are the spine of the page, not a footnote to it. A reading whose
  evidence you cannot walk back into is a paragraph you have to take on faith,
  and the whole point of doing this over a folder is that the folder is still
  right there to check against.
  """
  use MarginaliaWeb, :live_view

  alias Marginalia.Cuts

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Cuts.get_cut(user_id, id) do
      nil ->
        {:ok, socket |> put_flash(:error, "No such reading.") |> push_navigate(to: ~p"/cuts")}

      cut ->
        socket = assign(socket, page_title: cut.title, cut: cut, focus: nil)
        {:ok, if(cut.status == "draft", do: start_read(socket), else: socket)}
    end
  end

  defp start_read(socket) do
    user_id = socket.assigns.current_scope.user.id
    {:ok, cut} = Cuts.set_status(socket.assigns.cut, "reading")

    socket
    |> assign(cut: cut)
    |> start_async(:read, fn -> Cuts.read(cut, user_id) end)
  end

  defp reload(socket) do
    user_id = socket.assigns.current_scope.user.id
    assign(socket, cut: Cuts.get_cut(user_id, socket.assigns.cut.id))
  end

  @impl true
  def handle_async(:read, {:ok, {:ok, _}}, socket), do: {:noreply, reload(socket)}

  def handle_async(:read, {:ok, other}, socket),
    do: {:noreply, socket |> reload() |> put_flash(:error, "The read stopped: #{inspect(other)}")}

  def handle_async(:read, {:exit, reason}, socket) do
    {:ok, cut} = Cuts.set_status(socket.assigns.cut, "failed", inspect(reason))
    {:noreply, socket |> assign(cut: cut) |> put_flash(:error, "The read crashed.")}
  end

  @impl true
  def handle_event("again", _params, socket), do: {:noreply, start_read(socket)}

  def handle_event("focus", %{"n" => n}, socket) do
    n = String.to_integer(n)
    {:noreply, assign(socket, focus: if(socket.assigns.focus == n, do: nil, else: n))}
  end

  def handle_event("delete", _params, socket) do
    {:ok, _} = Cuts.delete_cut(socket.assigns.cut)
    {:noreply, socket |> put_flash(:info, "Reading deleted.") |> push_navigate(to: ~p"/cuts")}
  end

  # ==========================================================================

  @impl true
  def render(assigns) do
    user_id = assigns.current_scope.user.id

    assigns =
      assign(assigns,
        members: assigns.cut.members || [],
        stale: assigns.cut.status == "read" and not Cuts.current?(assigns.cut, user_id)
      )

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-3xl px-6 py-10">
        <div class="mg-meta"><.link navigate={~p"/cuts"}>← every reading</.link></div>
        <h1 style="font-family:var(--mg-serif)" class="mt-2 text-2xl font-semibold tracking-tight">
          {@cut.title}
        </h1>
        <p :if={@cut.question not in [nil, ""]} class="cut-ask">{@cut.question}</p>

        <%!-- who was read. Clicking one lights the claims that rest on it. --%>
        <div :if={@members != []} class="cut-members">
          <button
            :for={m <- @members}
            type="button"
            phx-click="focus"
            phx-value-n={m["n"]}
            class={"cut-member" <> if(@focus == m["n"], do: " on", else: "")}
          >
            <span class="i">{m["n"]}</span>
            <span class="l">{m["label"]}</span>
            <span :if={m["kind"] == "folder" and not m["read?"]} class="u">not read</span>
          </button>
        </div>
        <p :if={Enum.any?(@members, &(&1["kind"] == "folder" and not &1["read?"]))} class="cut-hole">
          Some of these have not been read yet, so this stands on their titles rather than
          on what they say. Read them first and this will be worth more.
        </p>

        <%= case @cut.status do %>
          <% "reading" -> %>
            <p class="cut-working">Reading this folder. One call, and it is the slow kind.</p>
          <% "failed" -> %>
            <p class="cut-err mt-6">
              {@cut.status_detail}
              <button class="mg-btn sm ghost ml-2" phx-click="again">try again</button>
            </p>
          <% "read" -> %>
            <p :if={@stale} class="cut-stale">
              This folder has changed since it was read.
              <button class="mg-btn sm ghost ml-2" phx-click="again">read again</button>
            </p>

            <h2 class="cut-h">Thesis</h2>
            <p class="cut-thesis">{@cut.thesis}</p>

            <.group title="Through-lines" items={@cut.threads} focus={@focus} />
            <.group title="Tensions" items={@cut.tensions} focus={@focus} />

            <div :if={@cut.not_supported not in [nil, ""]}>
              <h2 class="cut-h">What this does not show</h2>
              <p class="cut-body">{@cut.not_supported}</p>
            </div>
          <% _ -> %>
            <p class="cut-working">Queued.</p>
        <% end %>

        <div class="mt-10 flex flex-wrap items-center gap-2 border-t border-[var(--mg-rule)] pt-4">
          <button :if={@cut.status == "read"} class="mg-btn sm ghost" phx-click="again">
            read again
          </button>
          <span :if={@cut.dropped != []} class="mg-meta">
            {length(@cut.dropped)} claim{if length(@cut.dropped) == 1, do: "", else: "s"} dropped
            for quotes that could not be found
          </span>
          <button
            class="mg-btn sm ghost ml-auto"
            phx-click="delete"
            data-confirm="Delete this reading?"
          >delete</button>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :title, :string, required: true
  attr :items, :list, required: true
  attr :focus, :any, required: true

  defp group(assigns) do
    assigns = assign(assigns, :items, shown(assigns.items, assigns.focus))

    ~H"""
    <div :if={@items != []}>
      <h2 class="cut-h">{@title}</h2>
      <div :for={item <- @items} class="cut-claim">
        <p class="c">{item["claim"]}</p>
        <blockquote :for={ev <- item["evidence"] || []}>
          {ev["quote"]}
          <cite>{ev["label"] || "member #{ev["member"]}"}</cite>
        </blockquote>
      </div>
    </div>
    """
  end

  # Focusing a member narrows to the claims that actually cite it — the
  # question "what is this one doing here" answered by subtraction.
  defp shown(items, nil), do: items || []

  defp shown(items, n) do
    (items || [])
    |> Enum.filter(fn i ->
      Enum.any?(i["evidence"] || [], &(&1["member"] == n))
    end)
  end
end
