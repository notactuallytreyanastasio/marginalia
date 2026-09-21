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

  alias Marginalia.{Folders, Markdown, Stacks}

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
         count: length(steps),
         # A published reading is a page anybody can open, and the documents
         # behind it are not. The way back to them is shown only to the
         # writer, because a draft's slug *is* the permission to read it and
         # printing one on a public page gives it away.
         mine?: mine?(folder, socket.assigns[:current_scope])
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

        <p :if={@mine?} class="mg-meta st-yours">
          Yours. <.link navigate={~p"/stacks/#{@folder.id}"}>Open the folder</.link>
          to read it forwards again, compose it again, or get at any of the {@count} drafts.
        </p>

        <div class="lede md st-md">{Markdown.to_html(@story.opening)}</div>

        <section :for={{m, i} <- Enum.with_index(@story.movements, 1)} class="st-move">
          <h2><span class="n">{i}</span>{m["heading"]}</h2>
          <%!-- The model writes markdown whether or not anyone asked it to, and
                this prose is thick with identifiers in backticks. Rendered as
                plain text they show up as literal backticks. --%>
          <div class="md st-md">{Markdown.to_html(m["prose"])}</div>

          <aside :if={m["turn"] not in [nil, ""]} class="st-turn md st-md">
            {Markdown.to_html(m["turn"])}
          </aside>

          <nav :if={m["steps"] != []} class="st-move-steps">
            <span class="mg-label">from</span>
            <.link
              :for={n <- m["steps"]}
              navigate={~p"/reading/#{@folder.slug}/#{n}"}
              title={cap(@steps, n)}
            >{n}</.link>
          </nav>
        </section>

        <div class="st-closing md st-md">{Markdown.to_html(@story.closing)}</div>
      </article>
    </Layouts.app>
    """
  end

  defp mine?(%{user_id: uid}, %{user: %{id: uid}}) when not is_nil(uid), do: true
  defp mine?(_folder, _scope), do: false

  defp cap(steps, n) do
    case Map.get(steps, n) do
      nil -> "step #{n}"
      s -> s.capability
    end
  end
end
