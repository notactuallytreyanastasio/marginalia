defmodule MarginaliaWeb.StackLive.Story do
  @moduledoc """
  The long-form telling, read as one thing.

  Every part carries the steps it tells, so a reader who wants the detail
  behind a paragraph can leave for it and come back. That is the whole
  relationship between this page and the step pages: this one is the argument,
  those are the evidence, and neither pretends to be the other.
  """
  use MarginaliaWeb, :live_view

  alias Marginalia.{Folders, Markdown, Stacks}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user_id = socket.assigns.current_scope.user.id

    with %{} = folder <- Folders.get_folder(user_id, id),
         %{} = story <- Stacks.get_story(folder.id) do
      {:ok,
       assign(socket,
         page_title: story.title || folder.name,
         folder: folder,
         story: story,
         steps: Map.new(Stacks.list_steps(folder.id), &{&1.ordinal, &1}),
         stale: not Stacks.story_current?(story, folder.id)
       )}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, "No telling for that folder yet.")
         |> push_navigate(to: ~p"/stacks")}
    end
  end

  @impl true
  def handle_event("to-draft", _params, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Stacks.to_draft(user_id, socket.assigns.folder.id) do
      {:ok, work} ->
        {:noreply,
         socket
         |> put_flash(:info, "Opened as a draft. Read it the way you would anything else.")
         |> push_navigate(to: ~p"/works/#{work.slug}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not open it as a draft: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <article class="st-story">
        <div class="mg-meta">
          <.link navigate={~p"/stacks/#{@folder.id}"}>← {@folder.name}</.link>
        </div>

        <h1>{@story.title}</h1>

        <%!-- The one document here nobody could argue with in the margin was
              the one this application wrote. --%>
        <p class="mg-meta">
          <button phx-click="to-draft" class="mg-btn sm">Open as a draft</button>
          <span class="ml-2">a copy, read and annotated like any other manuscript</span>
        </p>

        <p :if={@stale} class="cut-stale">
          The steps have been re-read since this was composed.
        </p>
        <p :if={@story.uncovered != []} class="cut-stale">
          {length(@story.uncovered)} step{if length(@story.uncovered) == 1, do: "", else: "s"} found no place in this telling: {Enum.join(
            @story.uncovered,
            ", "
          )}. The composition
          is incomplete, not the stack.
        </p>

        <div class="lede md st-md">{Markdown.to_html(@story.opening)}</div>

        <section :for={{m, i} <- Enum.with_index(@story.movements, 1)} class="st-move">
          <h2><span class="n">{i}</span>{m["heading"]}</h2>
          <div class="md st-md">{Markdown.to_html(m["prose"])}</div>

          <aside :if={m["turn"] not in [nil, ""]} class="st-turn md st-md">
            {Markdown.to_html(m["turn"])}
          </aside>

          <nav :if={m["steps"] != []} class="st-move-steps">
            <span class="mg-label">from</span>
            <.link
              :for={n <- m["steps"]}
              navigate={~p"/stacks/#{@folder.id}/#{n}"}
              title={cap(@steps, n)}
            >{n}</.link>
          </nav>
        </section>

        <div class="st-closing md st-md">{Markdown.to_html(@story.closing)}</div>

        <p :if={@story.dropped != []} class="mg-meta st-drops">
          {length(@story.dropped)} problem{if length(@story.dropped) == 1, do: "", else: "s"} with the composition: {Enum.join(
            @story.dropped,
            "; "
          )}
        </p>
      </article>
    </Layouts.app>
    """
  end

  defp cap(steps, n) do
    case Map.get(steps, n) do
      nil -> "step #{n}"
      s -> s.capability
    end
  end
end
