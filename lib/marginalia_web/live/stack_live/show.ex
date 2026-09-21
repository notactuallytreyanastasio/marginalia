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

  alias Marginalia.{Folders, Runs, Stacks}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Folders.get_folder(user_id, id) do
      nil ->
        {:ok, socket |> put_flash(:error, "No such folder.") |> push_navigate(to: ~p"/stacks")}

      folder ->
        # A pass takes minutes to hours and belongs to the folder, not to
        # this socket. Whatever is running was started by some page that may
        # be closed by now; this one picks it up where it is.
        if connected?(socket), do: Runs.subscribe(key(folder.id))

        {:ok, socket |> assign(folder: folder) |> from_run(Runs.get(key(folder.id))) |> load()}
    end
  end

  defp key(folder_id), do: {:stack, folder_id}

  # The two things the buttons read, derived from the run rather than set
  # beside it, so a page that mounts into a pass in flight and a page that
  # started one show the same thing.
  defp from_run(socket, nil), do: assign(socket, reading: nil, composing: false, stage: nil)

  defp from_run(socket, %{kind: :compose} = run),
    do: assign(socket, reading: nil, composing: true, stage: stage_of(run))

  defp from_run(socket, %{kind: kind} = run) when kind in [:read, :deepen],
    do: assign(socket, reading: {run.done, run.total || 0}, composing: false, stage: nil)

  defp stage_of(%{stage: "outlining"}), do: "outlining"

  defp stage_of(%{stage: "writing", done: d, total: t}) when is_integer(t),
    do: "part #{d} of #{t}"

  defp stage_of(_), do: nil

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

  # Publishing is an explicit act and the folder has to belong to the account
  # this deploy belongs to — see Folders.publish/2. The same writer's
  # contracts sit in folders beside this one.
  def handle_event("publish", _params, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Marginalia.Folders.publish(user_id, socket.assigns.folder.id) do
      {:ok, folder} ->
        {:noreply,
         socket
         |> assign(folder: folder)
         |> put_flash(:info, "Published at /reading/#{folder.slug}")}

      {:error, :not_owner} ->
        {:noreply,
         put_flash(socket, :error, "Only the account this deploy belongs to can publish.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not publish: #{inspect(reason)}")}
    end
  end

  def handle_event("unpublish", _params, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Marginalia.Folders.unpublish(user_id, socket.assigns.folder.id) do
      {:ok, folder} ->
        {:noreply,
         socket |> assign(folder: folder) |> put_flash(:info, "Taken off the public site.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not unpublish: #{inspect(reason)}")}
    end
  end

  # Every pass goes through Marginalia.Runs, which puts it under the
  # application's task supervisor rather than this socket's process. The
  # page is then a viewer of the run and not its owner: closing the tab,
  # losing the connection or pressing reload no longer destroys two hours of
  # sequential model calls that have already been paid for.
  @impl true
  def handle_event("compose", _params, socket) do
    folder = socket.assigns.folder
    id = folder.id

    run(socket, :compose, fn ->
      Stacks.compose(id,
        building: folder.name,
        on_stage: fn stage, done, total ->
          Runs.progress(key(id), stage: stage, done: done, total: total)
        end
      )
      |> then(fn
        {:ok, _story} -> :ok
        other -> other
      end)
    end)
  end

  def handle_event("deepen", _params, socket) do
    id = socket.assigns.folder.id
    total = socket.assigns.stats.read

    run(socket, :deepen, fn ->
      {_steps, errors} =
        Stacks.deepen_stack(id,
          on_step: fn _s, i, _t -> Runs.progress(key(id), done: i, total: total) end
        )

      {:errors, length(errors)}
    end)
  end

  def handle_event("read", _params, socket) do
    user_id = socket.assigns.current_scope.user.id
    id = socket.assigns.folder.id
    total = socket.assigns.stats.documents

    run(socket, :read, fn ->
      {_steps, errors} =
        Stacks.read_stack(user_id, id,
          on_step: fn _step, i, _t -> Runs.progress(key(id), done: i, total: total) end
        )

      {:errors, length(errors)}
    end)
  end

  # The return value is deliberately tiny. It is broadcast to every page
  # watching this folder, and a list of every step of a stack is the stack
  # copied into each of them.
  defp run(socket, kind, fun) do
    id = socket.assigns.folder.id
    total = if kind == :compose, do: nil, else: socket.assigns.stats.documents

    case Runs.start(key(id), kind, fun) do
      {:ok, _run} ->
        {:noreply, from_run(socket, %{kind: kind, done: 0, total: total, stage: nil})}

      {:error, {:already_running, other}} ->
        {:noreply,
         socket
         |> from_run(Runs.get(key(id)))
         |> put_flash(:error, "A #{other} pass is already running on this folder.")}
    end
  end

  @impl true
  def handle_info({:run, :started, run}, socket),
    do: {:noreply, from_run(socket, run)}

  def handle_info({:run, :progress, run}, socket),
    do: {:noreply, from_run(socket, run)}

  def handle_info({:run, :done, _kind, {:errors, 0}}, socket),
    do: {:noreply, socket |> from_run(nil) |> load()}

  def handle_info({:run, :done, _kind, {:errors, n}}, socket) do
    {:noreply,
     socket
     |> from_run(nil)
     |> load()
     |> put_flash(:error, "#{n} document(s) did not read.")}
  end

  def handle_info({:run, :done, kind, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> from_run(nil)
     |> load()
     |> put_flash(:error, "The #{kind} pass failed: #{inspect(reason)}")}
  end

  def handle_info({:run, :done, _kind, _result}, socket),
    do: {:noreply, socket |> from_run(nil) |> load()}

  def handle_info({:run, :crashed, kind, _reason}, socket) do
    {:noreply,
     socket
     |> from_run(nil)
     |> load()
     |> put_flash(:error, "The #{kind} pass crashed. What finished is saved.")}
  end

  # The handle_async clauses that used to be here are gone with start_async.
  # A pass that fails or crashes is now a {:run, :done, _, {:error, _}} or a
  # {:run, :crashed, _, _} above, which reaches every page watching the
  # folder rather than only the one that pressed the button.

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
              from
              <.link navigate={~p"/works/#{@entry.step.work.slug}"}>{@entry.step.work.title}</.link>
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
            <.link
              :if={@entry.previous}
              navigate={~p"/stacks/#{@folder.id}/#{@entry.previous.ordinal}"}
            >
              ← {@entry.previous.capability}
            </.link>
            <span :if={is_nil(@entry.previous)}></span>
            <.link
              :if={@entry.next}
              navigate={~p"/stacks/#{@folder.id}/#{@entry.next.ordinal}"}
              class="next"
            >
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
          {@stats.documents} documents · {@stats.read} read · {@stats.pitfalls} pitfalls · {@stats.links} dependencies
          <span :if={@stats.deepened > 0}>
            · {@stats.deepened} deepened · {@stats.revisions} revised later
          </span>
          <span :if={@stats.deep_failed > 0} class="cut-err">
            · {@stats.deep_failed} failed the second pass
          </span>
          <span :if={@stats.dropped > 0}>· {@stats.dropped} claims dropped</span>
        </div>

        <div class="mt-5 flex items-center gap-3">
          <button class="mg-btn" phx-click="read" disabled={@reading != nil or @composing}>
            {if @stats.read > 0, do: "Read forwards again", else: "Read forwards"}
          </button>
          <button
            :if={@stats.read > 0}
            class="mg-btn ghost"
            phx-click="deepen"
            disabled={@reading != nil or @composing}
          >
            {cond do
              @stats.deep_failed > 0 -> "Retry #{@stats.deep_failed} failed"
              @stats.deepened > 0 -> "Deepen again"
              true -> "Second pass"
            end}
          </button>
          <button
            :if={@stats.read > 0}
            class="mg-btn ghost"
            phx-click="compose"
            disabled={@reading != nil or @composing}
          >
            {cond do
              @composing and @stage -> "Composing — #{@stage}"
              @composing -> "Composing…"
              @story -> "Compose again"
              true -> "Compose the telling"
            end}
          </button>
          <span :if={@reading} class="mg-meta">
            {elem(@reading, 0)} of {elem(@reading, 1)} — each document waits on the one before it.
            This runs on the server: you can close the page.
          </span>
        </div>

        <p :if={@composing} class="mg-meta mt-2">
          <b :if={@stage}>Composing — {@stage}.</b>
          Composing runs on the server too. Leave, come back, open it on your phone — the
          page finds the pass still going. A deploy is the one thing that stops it.
        </p>

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

            <div class="mg-meta st-publish">
              <%= if @folder.published_at do %>
                public at
                <.link navigate={~p"/reading/#{@folder.slug}"}>/reading/{@folder.slug}</.link>
                <button phx-click="unpublish" class="mg-btn sm ml-2">Make private</button>
              <% else %>
                <button
                  phx-click="publish"
                  data-confirm="Publish this stack? Anyone with the link will be able to read the telling and every step of it."
                  class="mg-btn sm"
                >Publish</button>
                <span class="ml-2">private — only you can read it</span>
              <% end %>
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
