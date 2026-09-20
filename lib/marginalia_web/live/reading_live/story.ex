defmodule MarginaliaWeb.ReadingLive.Story do
  @moduledoc """
  A published stack's telling, read by anybody.

  The same story `StackLive.Story` shows its owner, addressed by slug rather
  than folder id and with nothing on it that writes. It is a separate module
  rather than a flag on that one because the private page carries the
  buttons that spend money — read, deepen, compose — and the safe way to
  keep those off a public page is for the public page not to have them.
  """
  use MarginaliaWeb, :live_view

  alias Marginalia.{Folders, Stacks}

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    with %{} = folder <- Folders.get_published(slug),
         %{} = story <- Stacks.get_story(folder.id) do
      steps = Stacks.list_steps(folder.id)

      {:ok,
       assign(socket,
         page_title: story.title || folder.name,
         page_description: String.slice(story.opening || "", 0, 300),
         folder: folder,
         story: story,
         steps: Map.new(steps, &{&1.ordinal, &1}),
         count: length(steps)
       )}
    else
      _ ->
        {:ok, socket |> put_flash(:error, "No such reading.") |> push_navigate(to: ~p"/reading")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <article class="st-story">
        <div class="mg-meta">
          <.link navigate={~p"/reading"}>← Readings</.link>
        </div>

        <h1>{@story.title}</h1>

        <p class="mg-meta">
          {@count} documents, read forwards. {@folder.name}
        </p>

        <div class="lede">{@story.opening}</div>

        <section :for={{m, i} <- Enum.with_index(@story.movements, 1)} class="st-move">
          <h2><span class="n">{i}</span>{m["heading"]}</h2>
          <p :for={para <- paras(m["prose"])}>{para}</p>

          <aside :if={m["turn"] not in [nil, ""]} class="st-turn">{m["turn"]}</aside>

          <nav :if={m["steps"] != []} class="st-move-steps">
            <span class="mg-label">from</span>
            <.link
              :for={n <- m["steps"]}
              navigate={~p"/reading/#{@folder.slug}/#{n}"}
              title={cap(@steps, n)}
            >{n}</.link>
          </nav>
        </section>

        <div class="st-closing">{@story.closing}</div>
      </article>
    </Layouts.app>
    """
  end

  defp paras(nil), do: []
  defp paras(text), do: text |> String.split(~r/\n{2,}/, trim: true) |> Enum.map(&String.trim/1)

  defp cap(steps, n) do
    case Map.get(steps, n) do
      nil -> "step #{n}"
      s -> s.capability
    end
  end
end
