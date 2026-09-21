defmodule MarginaliaWeb.ReadingLive.Step do
  @moduledoc """
  One step of a published stack: what to do at this point, and what not to.

  The story is the argument and these are the evidence. A reader who doubts
  a paragraph of the telling comes here, where the claim is attached to the
  document it was read out of and the quotes are ones that were located in
  that document before they were kept.
  """
  use MarginaliaWeb, :live_view

  alias Marginalia.{Folders, Markdown, Stacks, Works}

  @impl true
  def mount(%{"slug" => slug, "ordinal" => ordinal}, _session, socket) do
    with %{} = folder <- Folders.get_published(slug),
         {n, ""} <- Integer.parse(ordinal),
         guide <- Stacks.guide(folder.id),
         %{} = entry <- Enum.find(guide, &(&1.step.ordinal == n)) do
      {:ok,
       assign(socket,
         page_title: entry.step.capability,
         folder: folder,
         entry: entry,
         count: length(guide),
         story: Stacks.get_story(folder.id),
         # The document this step was read out of, and only for the writer.
         # `get_work/2` is the owner-scoped lookup, so a visitor gets nil
         # rather than a link — a draft's slug is the permission to read it,
         # and this page is public.
         source: source(entry, socket.assigns[:current_scope])
       )}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, "No such step.")
         |> push_navigate(to: ~p"/reading")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <article class="st-step">
        <div class="mg-meta">
          <.link navigate={~p"/reading/#{@folder.slug}"}>← {(@story && @story.title) || @folder.name}</.link>
        </div>

        <span class="n">Step {@entry.step.ordinal} of {@count}</span>
        <h1>{@entry.step.capability}</h1>

        <p :if={@source} class="mg-meta st-yours">
          Read out of <.link navigate={~p"/works/#{@source.slug}?view=read"}>{@source.title}</.link>,
          which is yours to edit.
        </p>

        <section :if={@entry.step.lesson}>
          <h2 class="mg-label">What to do</h2>
          <div class="md st-md">{Markdown.to_html(@entry.step.lesson)}</div>
        </section>

        <section :if={@entry.step.mechanism}>
          <h2 class="mg-label">How it works</h2>
          <div class="md st-md">{Markdown.to_html(@entry.step.mechanism)}</div>
        </section>

        <section :if={@entry.step.pitfall not in [nil, ""]} class="st-pitfall">
          <h2 class="mg-label">The obvious version is wrong</h2>
          <div class="md st-md">{Markdown.to_html(@entry.step.pitfall)}</div>
          <blockquote :if={@entry.step.pitfall_quote not in [nil, ""]}>
            {@entry.step.pitfall_quote}
          </blockquote>
        </section>

        <section :if={@entry.step.watch_for}>
          <h2 class="mg-label">Get right now</h2>
          <div class="md st-md">{Markdown.to_html(@entry.step.watch_for)}</div>
        </section>

        <section :if={@entry.step.revised_by} class="st-revision">
          <h2 class="mg-label">Walked back by step {@entry.step.revised_by}</h2>
          <div class="md st-md">{Markdown.to_html(@entry.step.revision)}</div>
          <blockquote :if={@entry.step.revision_quote not in [nil, ""]}>
            {@entry.step.revision_quote}
          </blockquote>
        </section>

        <section :if={@entry.step.excerpts != []}>
          <h2 class="mg-label">From the document</h2>
          <%!-- "text" is the passage the quote was located in, not the model's
                quote: validate/3 stores the surrounding block so a reader sees
                the claim in its context rather than the sentence alone. --%>
          <figure :for={e <- @entry.step.excerpts} class="st-excerpt">
            <pre><code>{e["text"]}</code></pre>
            <figcaption :if={e["caption"] not in [nil, ""]}>{e["caption"]}</figcaption>
          </figure>
        </section>

        <nav :if={@entry.requires != []} class="st-move-steps">
          <span class="mg-label">stands on</span>
          <.link :for={r <- @entry.requires} navigate={~p"/reading/#{@folder.slug}/#{r.ordinal}"}>
            {r.ordinal}
          </.link>
        </nav>

        <nav class="st-nav">
          <.link
            :if={@entry.previous}
            navigate={~p"/reading/#{@folder.slug}/#{@entry.previous.ordinal}"}
          >
            ← {@entry.previous.ordinal}. {@entry.previous.capability}
          </.link>
          <.link :if={@entry.next} navigate={~p"/reading/#{@folder.slug}/#{@entry.next.ordinal}"}>
            {@entry.next.ordinal}. {@entry.next.capability} →
          </.link>
        </nav>
      </article>
    </Layouts.app>
    """
  end

  defp source(%{step: %{work_id: work_id}}, %{user: %{id: user_id}}) when not is_nil(work_id),
    do: Works.get_work(user_id, work_id)

  defp source(_entry, _scope), do: nil
end
