defmodule MarginaliaWeb.CutLive.New do
  @moduledoc """
  Drawing a line through several drafts.

  The reading view puts one draft beside its margin. This puts four beside
  each other and asks the reader to point at the paragraphs that belong
  together. Everything about the layout follows from that: the drafts are a
  rail you move along, the passages are the page, and what you have picked so
  far never leaves the screen — a cut you cannot see while choosing is a cut
  you cannot reason about.
  """
  use MarginaliaWeb, :live_view

  alias Marginalia.{Cuts, Folders, Works}

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.id
    works = Works.list_works(user_id)

    {:ok,
     socket
     |> assign(
       page_title: "New cut",
       works: works,
       folders: Folders.list_folders(user_id),
       folder_id: nil,
       open: nil,
       blocks: [],
       picks: [],
       title: "",
       question: "",
       error: nil
     )
     |> open_work(List.first(works))}
  end

  defp open_work(socket, nil), do: assign(socket, open: nil, blocks: [])

  defp open_work(socket, work) do
    assign(socket, open: work, blocks: Cuts.blocks(work))
  end

  defp shown(socket) do
    case socket.assigns.folder_id do
      nil -> socket.assigns.works
      id -> Enum.filter(socket.assigns.works, &(&1.folder_id == id))
    end
  end

  defp picked?(picks, work_id, ref),
    do: Enum.any?(picks, &(&1.work_id == work_id and &1.ref == ref))

  # ==========================================================================

  @impl true
  def handle_event("folder", %{"id" => id}, socket) do
    folder_id = if id in ["", "all"], do: nil, else: String.to_integer(id)
    socket = assign(socket, folder_id: folder_id)
    {:noreply, open_work(socket, List.first(shown(socket)))}
  end

  def handle_event("open", %{"id" => id}, socket) do
    work = Enum.find(socket.assigns.works, &(&1.id == String.to_integer(id)))
    {:noreply, open_work(socket, work)}
  end

  def handle_event("pick", %{"ref" => ref}, socket) do
    work = socket.assigns.open
    picks = socket.assigns.picks

    picks =
      if picked?(picks, work.id, ref) do
        Enum.reject(picks, &(&1.work_id == work.id and &1.ref == ref))
      else
        block = Enum.find(socket.assigns.blocks, &(&1.ref == ref))
        picks ++ [%{work_id: work.id, title: work.title, ref: ref, text: block.text}]
      end

    {:noreply, assign(socket, picks: picks, error: nil)}
  end

  def handle_event("drop", %{"work" => work_id, "ref" => ref}, socket) do
    work_id = String.to_integer(work_id)

    {:noreply,
     assign(socket,
       picks: Enum.reject(socket.assigns.picks, &(&1.work_id == work_id and &1.ref == ref))
     )}
  end

  def handle_event("clear", _params, socket), do: {:noreply, assign(socket, picks: [])}

  def handle_event("form", %{"title" => title, "question" => question}, socket) do
    {:noreply, assign(socket, title: title, question: question)}
  end

  def handle_event("read", %{"title" => title, "question" => question}, socket) do
    user_id = socket.assigns.current_scope.user.id
    picks = Enum.map(socket.assigns.picks, &{&1.work_id, &1.ref})

    cond do
      String.trim(title) == "" ->
        {:noreply, assign(socket, error: "Give the cut a name.", title: title)}

      picks == [] ->
        {:noreply, assign(socket, error: "Pick some passages first.")}

      true ->
        case Cuts.create_cut(user_id, %{"title" => title, "question" => question}, picks) do
          {:ok, cut} -> {:noreply, push_navigate(socket, to: ~p"/cuts/#{cut.id}")}
          {:error, _} -> {:noreply, assign(socket, error: "That did not work.")}
        end
    end
  end

  # ==========================================================================

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :shown, shown_for(assigns))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="cut">
        <div class="cut-bar">
          <h1 style="font-family:var(--mg-serif)" class="text-xl font-semibold">New cut</h1>
          <span class="mg-meta">a line through several drafts at once</span>
          <form phx-change="folder" class="ml-auto">
            <select name="id" class="mg-select sm">
              <option value="all" selected={@folder_id == nil}>Every draft</option>
              <option :for={f <- @folders} value={f.id} selected={@folder_id == f.id}>
                {f.name}
              </option>
            </select>
          </form>
          <.link navigate={~p"/cuts"} class="mg-btn sm ghost">All cuts</.link>
        </div>

        <div class="cut-grid">
          <nav class="cut-rail">
            <p :if={@shown == []} class="mg-empty p-3">No drafts here.</p>
            <button
              :for={w <- @shown}
              type="button"
              phx-click="open"
              phx-value-id={w.id}
              class={"cut-doc" <> if(@open && @open.id == w.id, do: " on", else: "")}
            >
              <span class="t">{w.title}</span>
              <span :if={count_for(@picks, w.id) > 0} class="n">{count_for(@picks, w.id)}</span>
            </button>
          </nav>

          <section class="cut-page">
            <%= if @open do %>
              <h2 style="font-family:var(--mg-serif)" class="text-lg mb-1">{@open.title}</h2>
              <div class="mg-meta mb-4">{@open.word_count} words · click a passage to add it</div>
              <div
                :for={b <- @blocks}
                class={"cut-blk" <> if(picked?(@picks, @open.id, b.ref), do: " on", else: "")}
                phx-click="pick"
                phx-value-ref={b.ref}
              >
                <span class="ref">{b.ref}</span>{b.text}
              </div>
            <% else %>
              <p class="mg-empty">Pick a draft on the left.</p>
            <% end %>
          </section>

          <aside class="cut-tray">
            <h2 style="font-family:var(--mg-serif)" class="text-base">
              {length(@picks)} passage{if length(@picks) == 1, do: "", else: "s"}
            </h2>
            <p :if={@picks == []} class="mg-empty">
              Click passages in any draft. Pick from more than one — a cut only reports what
              holds across two or more.
            </p>

            <div :if={@picks != []} class="cut-picks">
              <div :for={{title, group} <- grouped(@picks)} class="cut-group">
                <div class="mg-label">{title}</div>
                <div :for={p <- group} class="cut-pick">
                  <span class="r">{p.ref}</span>
                  <span class="t">{String.slice(p.text, 0, 110)}</span>
                  <button
                    class="x"
                    phx-click="drop"
                    phx-value-work={p.work_id}
                    phx-value-ref={p.ref}
                  >×</button>
                </div>
              </div>
            </div>

            <form :if={@picks != []} phx-submit="read" phx-change="form" class="cut-form">
              <input
                type="text"
                name="title"
                value={@title}
                placeholder="Name this cut"
                autocomplete="off"
                class="mg-input"
              />
              <textarea
                name="question"
                rows="3"
                placeholder="What do you want to know about these together? (optional)"
                class="mg-textarea"
              >{@question}</textarea>
              <p :if={@error} class="cut-err">{@error}</p>
              <p :if={distinct(@picks) < 2} class="mg-meta">
                Only one draft so far — a cut wants at least two.
              </p>
              <div class="flex gap-2">
                <button class="mg-btn" type="submit">Read this cut</button>
                <button class="mg-btn ghost" type="button" phx-click="clear">Clear</button>
              </div>
            </form>
          </aside>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp shown_for(%{folder_id: nil, works: works}), do: works
  defp shown_for(%{folder_id: id, works: works}), do: Enum.filter(works, &(&1.folder_id == id))

  defp count_for(picks, work_id), do: Enum.count(picks, &(&1.work_id == work_id))
  defp distinct(picks), do: picks |> Enum.map(& &1.work_id) |> Enum.uniq() |> length()

  defp grouped(picks) do
    picks
    |> Enum.group_by(& &1.title)
    |> Enum.sort_by(fn {title, _} -> title end)
  end
end
