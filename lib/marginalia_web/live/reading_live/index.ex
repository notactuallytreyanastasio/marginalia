defmodule MarginaliaWeb.ReadingLive.Index do
  @moduledoc """
  The published readings, whoever is looking.

  A folder is private until somebody publishes it, so this is empty on a
  fresh deploy and stays empty until an explicit act. That is the same rule
  `Marginalia.Cases` follows and for the same reason: nothing here appears
  by accident.
  """
  use MarginaliaWeb, :live_view

  alias Marginalia.{Folders, Stacks}

  @impl true
  def mount(_params, _session, socket) do
    readings =
      Folders.published()
      |> Enum.map(fn f ->
        %{folder: f, story: Stacks.get_story(f.id), steps: Stacks.list_steps(f.id)}
      end)
      |> Enum.filter(& &1.story)

    {:ok,
     assign(socket,
       page_title: "Readings",
       page_description:
         "Series of documents read forwards, so that what they add up to is a method somebody else can follow.",
       readings: readings
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="lx">
        <h1>Readings</h1>
        <p class="lede">
          A series of documents read <em>forwards</em> — each one told only what the ones
          before it established. Read that way, each says what somebody building the same
          thing must now do, and no single document contains it.
        </p>

        <p :if={@readings == []} class="mg-empty">Nothing published yet.</p>

        <ul class="mg-rows">
          <li :for={r <- @readings}>
            <.link navigate={~p"/reading/#{r.folder.slug}"} class="t">{r.story.title}</.link>
            <p class="mg-meta">
              {length(r.steps)} documents · {length(r.story.movements)} parts · {r.folder.name}
            </p>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end
end
