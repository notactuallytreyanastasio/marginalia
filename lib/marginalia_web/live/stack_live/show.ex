defmodule MarginaliaWeb.StackLive.Show do
  @moduledoc """
  A stack read forwards: the chain of capabilities, and a page per step.

  Two views of one thing. The chain is the method at a glance — what the
  reader will be able to do after each document, in order. A step is the page
  they actually work from: what to do, what goes wrong if they do the obvious
  thing instead, the passage from the document itself, and links backwards to
  what it stands on and forwards to what stands on it.
  """
  use MarginaliaWeb, :live_view

  alias Marginalia.{Folders, Stacks}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Folders.get_folder(user_id, id) do
      nil ->
        {:ok, socket |> put_flash(:error, "No such folder.") |> push_navigate(to: ~p"/stacks")}

      folder ->
        {:ok, socket |> assign(folder: folder, reading: nil, composing: false) |> load()}
    end
  end

  defp load(socket) do
    user_id = socket.assigns.current_scope.user.id
    folder = socket.assigns.folder

    assign(socket,
      page_title: folder.name,
      story: Stacks.get_story(folder.id),
      guide: Stacks.guide(folder.id),
      documents: Stacks.documents(user_id, folder.id),
      stats: Stacks.stats(user_id, folder.id)
    )
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, ordinal: params["ordinal"] && String.to_integer(params["ordinal"]))}
  end

  # ==========================================================================

  @impl true
  def handle_event("compose", _params, socket) do
    folder = socket.assigns.folder

    {:noreply,
     socket
     |> assign(composing: true)
     |> start_async(:compose, fn -> Stacks.compose(folder.id, building: folder.name) end)}
  end

  def handle_event("deepen", _params, socket) do
    folder_id = socket.assigns.folder.id
    lv = self()

    {:noreply,
     socket
     |> assign(reading: {0, socket.assigns.stats.read})
     |> start_async(:read, fn ->
       Stacks.deepen_stack(folder_id,
         on_step: fn _s, i, total -> send(lv, {:step_done, i, total}) end
       )
     end)}
  end

  def handle_event("read", _params, socket) do
    user_id = socket.assigns.current_scope.user.id
    folder_id = socket.assigns.folder.id
    lv = self()

    {:noreply,
     socket
     |> assign(reading: {0, socket.assigns.stats.documents})
     |> start_async(:read, fn ->
       Stacks.read_stack(user_id, folder_id,
         on_step: fn _step, i, total -> send(lv, {:step_done, i, total}) end
       )
     end)}
  end

  @impl true
  def handle_info({:step_done, i, total}, socket),
    do: {:noreply, assign(socket, reading: {i, total})}

  @impl true
  def handle_async(:read, {:ok, {_steps, errors}}, socket) do
    socket = socket |> assign(reading: nil) |> load()

    {:noreply,
     if errors == [] do
       socket
     else
       put_flash(socket, :error, "#{length(errors)} document(s) did not read.")
     end}
  end

  def handle_async(:compose, {:ok, {:ok, _story}}, socket),
    do: {:noreply, socket |> assign(composing: false) |> load()}

  def handle_async(:compose, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(composing: false)
     |> put_flash(:error, "Could not compose: #{inspect(reason)}")}
  end

  def handle_async(:compose, {:exit, reason}, socket) do
    {:noreply,
     socket |> assign(composing: false) |> put_flash(:error, "Compose crashed: #{inspect(reason)}")}
  end

  def handle_async(:read, {:exit, reason}, socket) do
    {:noreply,
     socket |> assign(reading: nil) |> put_flash(:error, "The read crashed: #{inspect(reason)}")}
  end

  # ==========================================================================

  @impl true
  def render(%{ordinal: n} = assigns) when is_integer(n) do
    entry = Enum.find(assigns.guide, &(&1.step.ordinal == n))
    assigns = assign(assigns, entry: entry)

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-2xl px-6 py-10">
        <div class="mg-meta">
          <.link navigate={~p"/stacks/#{@folder.id}"}>← {@folder.name}</.link>
        </div>

        <%= if @entry do %>
          <div class="st-step-head">
            <span class="n">Step {@entry.step.ordinal} of {@stats.read}</span>
            <h1 style="font-family:var(--mg-serif)">{@entry.step.capability}</h1>
            <div class="mg-meta">
              from <.link navigate={~p"/works/#{@entry.step.work.slug}"}>{@entry.step.work.title}</.link>
            </div>
          </div>

          <h2 class="cut-h">What to do</h2>
          <p class="st-lesson">{@entry.step.lesson}</p>

          <div :if={@entry.step.mechanism}>
            <h2 class="cut-h">How it works</h2>
            <p class="st-lesson">{@entry.step.mechanism}</p>
          </div>

          <div :if={@entry.step.watch_for}>
            <h2 class="cut-h">Get this right now</h2>
            <p class="st-watch">{@entry.step.watch_for}</p>
          </div>

          <div :if={@entry.step.revised_by}>
            <h2 class="cut-h">A later step walks this back</h2>
            <p class="st-pitfall">{@entry.step.revision}</p>
            <blockquote class="st-quote">{@entry.step.revision_quote}</blockquote>
            <p class="mg-meta mt-1">
              <.link navigate={~p"/stacks/#{@folder.id}/#{@entry.step.revised_by}"}>
                read step {@entry.step.revised_by} →
              </.link>
            </p>
          </div>

          <div :if={@entry.step.pitfall}>
            <h2 class="cut-h">Why the obvious version is wrong</h2>
            <p class="st-pitfall">{@entry.step.pitfall}</p>
            <blockquote class="st-quote">{@entry.step.pitfall_quote}</blockquote>
          </div>

          <div :if={@entry.step.excerpts != []}>
            <h2 class="cut-h">From the document</h2>
            <figure :for={x <- @entry.step.excerpts} class="st-excerpt">
              <pre><code>{x["text"]}</code></pre>
              <figcaption :if={x["caption"] not in [nil, ""]}>{x["caption"]}</figcaption>
            </figure>
          </div>

          <div :if={@entry.requires != []}>
            <h2 class="cut-h">You need these first</h2>
            <.chain items={@entry.requires} folder={@folder} />
          </div>

          <div :if={@entry.required_by != []}>
            <h2 class="cut-h">What this makes possible</h2>
            <.chain items={@entry.required_by} folder={@folder} />
          </div>

          <nav class="st-nav">
            <.link :if={@entry.previous} navigate={~p"/stacks/#{@folder.id}/#{@entry.previous.ordinal}"}>
              ← {@entry.previous.capability}
            </.link>
            <span :if={is_nil(@entry.previous)}></span>
            <.link :if={@entry.next} navigate={~p"/stacks/#{@folder.id}/#{@entry.next.ordinal}"} class="next">
              {@entry.next.capability} →
            </.link>
          </nav>
        <% else %>
          <p class="mg-empty mt-8">No step {@ordinal} here.</p>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-3xl px-6 py-10">
        <div class="mg-meta"><.link navigate={~p"/stacks"}>← every method</.link></div>
        <h1 style="font-family:var(--mg-serif)" class="mt-2 text-2xl font-semibold tracking-tight">
          {@folder.name}
        </h1>
        <div class="mg-meta mt-1">
          {@stats.documents} documents · {@stats.read} read · {@stats.pitfalls} pitfalls ·
          {@stats.links} dependencies
          <span :if={@stats.deepened > 0}>
            · {@stats.deepened} deepened · {@stats.revisions} revised later
          </span>
          <span :if={@stats.dropped > 0}>· {@stats.dropped} claims dropped</span>
        </div>

        <div class="mt-5 flex items-center gap-3">
          <button class="mg-btn" phx-click="read" disabled={@reading != nil}>
            {if @stats.read > 0, do: "Read forwards again", else: "Read forwards"}
          </button>
          <button
            :if={@stats.read > 0}
            class="mg-btn ghost"
            phx-click="deepen"
            disabled={@reading != nil}
          >
            {if @stats.deepened > 0, do: "Deepen again", else: "Second pass"}
          </button>
          <button
            :if={@stats.read > 0}
            class="mg-btn ghost"
            phx-click="compose"
            disabled={@reading != nil or @composing}
          >
            {if @composing, do: "Composing…", else: if(@story, do: "Compose again", else: "Compose the telling")}
          </button>
          <span :if={@reading} class="mg-meta">
            {elem(@reading, 0)} of {elem(@reading, 1)} — each document waits on the one before it
          </span>
        </div>

        <p :if={@reading} class="st-progress" style={"--done:#{progress(@reading)}"}>
          <span></span>
        </p>

        <%= if @guide == [] do %>
          <p class="mg-empty mt-8">
            Not read yet. Reading is one call per document, in order, because each one is told
            what the ones before it established.
          </p>
          <ol class="st-docs mt-4">
            <li :for={{w, i} <- Enum.with_index(@documents, 1)}>
              <span class="n">{i}</span>{w.title}
            </li>
          </ol>
        <% else %>
          <div :if={@story} class="st-story-card">
            <div class="mg-label">The telling</div>
            <.link navigate={~p"/stacks/#{@folder.id}/story"} class="t">{@story.title}</.link>
            <div class="mg-meta">
              {length(@story.movements)} parts
              <span :if={@story.uncovered != []} class="cut-err">
                · {length(@story.uncovered)} steps left out
              </span>
              <span :if={not Stacks.story_current?(@story, @folder.id)} class="cut-err">· stale</span>
            </div>
          </div>

          <h2 class="cut-h">The method</h2>
          <ol class="st-chain">
            <li :for={e <- @guide} class={if e.step.pitfall, do: "has-pitfall", else: ""}>
              <.link navigate={~p"/stacks/#{@folder.id}/#{e.step.ordinal}"}>
                <span class="n">{e.step.ordinal}</span>
                <span class="c">{e.step.capability}</span>
              </.link>
              <span :if={e.requires != []} class="dep">
                needs {Enum.map_join(e.requires, ", ", &to_string(&1.ordinal))}
              </span>
              <span :if={e.step.revised_by} class="dep rev">
                revised by {e.step.revised_by}
              </span>
            </li>
          </ol>
          <p class="mg-meta mt-5">
            Start at step 1. Every step links back to what it stands on and forward to what
            stands on it.
            <span :if={@stats.deepened == 0}>
              The second pass adds how each one works, what to get right now, and where a
              later step walks it back — none of which the first pass can see.
            </span>
          </p>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp progress({done, total}) when total > 0, do: "#{round(done / total * 100)}%"
  defp progress(_), do: "0%"

  attr :items, :list, required: true
  attr :folder, :map, required: true

  defp chain(assigns) do
    ~H"""
    <ul class="st-links">
      <li :for={s <- @items}>
        <.link navigate={~p"/stacks/#{@folder.id}/#{s.ordinal}"}>
          <span class="n">{s.ordinal}</span>{s.capability}
        </.link>
      </li>
    </ul>
    """
  end
end
