defmodule Marginalia.Walkthrough do
  @moduledoc """
  A guided run through a view that actually works the controls.

  `Marginalia.Tour` is a card listing what a tab does. It is read once and
  believed or not. This is the other kind: it spotlights a control, presses
  it, and lets the page answer — because almost everything on the read view
  is an affordance you cannot see until it fires. A hairline that appears on
  hover, a selection that grows three buttons, a filter that changes what the
  margin is *about* rather than how much of it there is. Told about, they
  sound like nothing. Shown, they are the product.

  Two rules make that safe to run on somebody's real manuscript:

  1. **The model is never called.** Every answer the tour shows is a fixture
     in this module. A walkthrough that spent a paragraph of someone's quota
     to demonstrate a button would be a strange thing to build, and one that
     waited eight seconds on an API for each step would be worse.

  2. **Nothing is written.** The thread it opens is a struct that never
     reaches the database, the rewrite it shows is this file, and the edit it
     opens is thrown away. The writer ends the tour with exactly the draft
     they started it with.

  Both of those are stated on the card the whole way through rather than
  buried here, because a fixture presented as a reading of *your* draft is
  the one thing this product must never do.
  """

  # ------------------------------------------------------------------ steps

  @read [
    %{
      id: "margin",
      title: "The notes sit beside the line",
      body:
        "Every note is level with the sentence that caused it, and the highlight under the prose is the exact span it is anchored to — copied out of your draft character for character.",
      target: ".mg-read-rail .mg-note-slot",
      place: "left"
    },
    %{
      id: "filters",
      title: "The filter changes what the margin is about",
      body:
        "Watch the margin, not the tabs. Tensions leaves only the places the draft argues with itself. Beats is what it does, in order; Connections is what reaches across sections.",
      target: "#read-filters",
      place: "bottom",
      act: %{kind: "push", event: "set_only", params: %{"only" => "tensions"}}
    },
    %{
      id: "filters_back",
      title: "Everything, again",
      body:
        "Back to both passes at once, which is how it opens. The filter never removes a note from the draft — only from this view.",
      target: "#read-filters",
      place: "bottom",
      act: %{kind: "push", event: "set_only", params: %{"only" => "all"}}
    },
    %{
      id: "map",
      title: "A map of the draft, drawn to scale",
      body:
        "Each block is sized by its section's word count, so the shape of the thing is visible before you have read a line of it. Click any block to land there.",
      target: ".mg-map",
      place: "right",
      act: %{kind: "client", name: "open_map"}
    },
    %{
      id: "thread",
      title: "A thread pinned to one paragraph",
      body:
        "Move the pointer to the left edge of any paragraph and a hairline appears in the gutter. Clicking it opens a conversation about that paragraph, already holding it — and it is still there when you come back.",
      target: ".mg-read-body .mg-block",
      place: "right",
      act: %{kind: "client", name: "open_thread"}
    },
    %{
      id: "ask",
      owner: true,
      title: "Ask about that spot",
      body:
        "No re-explaining which bit you meant. The paragraph goes in as the subject of the question.",
      target: ".mg-thread-panel",
      place: "right",
      act: %{kind: "client", name: "ask_thread"}
    },
    %{
      id: "select",
      title: "Or select a passage",
      body:
        "Click and hold, then drag across any run of text. Three things come up at the end of it: talk about that spot, ask for rewrites of it, or carry it into the chat.",
      target: ".mg-read-body .mg-block",
      place: "right",
      act: %{kind: "client", name: "select"}
    },
    %{
      id: "rewrite",
      owner: true,
      title: "Three rewrites, each with its cost",
      body:
        "The one place it writes, and it only opens from your side. Hover a candidate to see it over your own line as a diff. Nothing is ever applied.",
      target: ".mg-rewrite",
      place: "right",
      act: %{kind: "client", name: "rewrite"}
    },
    %{
      id: "edit",
      owner: true,
      title: "Then answer it in your own words",
      body:
        "Click into any paragraph and it opens for editing, in the markdown you wrote it in. Start from a candidate or ignore them all. Saving is switched off for the tour.",
      target: ".mg-read-body .mg-block",
      place: "right",
      act: %{kind: "client", name: "edit"}
    },
    %{
      id: "done",
      title: "That is the read view",
      body:
        "The thread, the rewrite and the edit you just saw were never written down, and no model was called for any of it. Your draft is exactly as you left it. The ? in the header runs this again.",
      target: nil,
      place: "centre",
      act: %{kind: "client", name: "reset"}
    }
  ]

  @doc """
  The ordered steps for a view, or `[]` where there is no walkthrough yet.

  `mine?: false` drops the steps that only exist for the person who owns the
  draft. Someone reading a draft you sent them cannot type in a thread, ask
  for rewrites or edit a paragraph, and a walkthrough that mimed those would
  be teaching them an interface they do not have.
  """
  def steps(view, opts \\ [])
  def steps(:read, opts), do: filter(@read, opts)
  def steps(_, _), do: []

  defp filter(steps, opts) do
    if Keyword.get(opts, :mine?, true),
      do: steps,
      else: Enum.reject(steps, & &1[:owner])
  end

  @doc "Whether a view has one."
  def for_view?(view), do: steps(view, mine?: false) != []

  @doc "Views with a walkthrough, as the strings stored against an account."
  def views, do: ["read"]

  # --------------------------------------------------------------- fixtures

  @doc """
  What the tour shows instead of calling the model.

  Deliberately about a sample sentence rather than the writer's own. A
  fixture dressed up as a reading of the paragraph in front of them would
  teach them to distrust every real note on the page, which is the whole
  asset.
  """
  def rewrite do
    %{
      sample: true,
      reading:
        "The line is doing two jobs: announcing that something changed, and holding back what it was.",
      original:
        "It was, in a sense, the beginning of something that would eventually change everything about the way she saw her father.",
      section: nil,
      # the same atom keys `Marginalia.Rewrite.clean/2` produces, so the panel
      # renders a fixture through exactly the code path a real answer takes
      candidates: [
        %{
          text: "It changed how she saw her father.",
          move: "Cuts the gloss",
          cost: "Loses the narrator's distance from the moment"
        },
        %{
          text: "She would not see her father the same way again, and this was where it started.",
          move: "Puts the change last",
          cost: "Slower into the paragraph that follows"
        },
        %{
          text: "She watched him back the car out, and something in it went.",
          move: "Hands it to the image",
          cost: "Only works if the car is already in the scene"
        }
      ]
    }
  end

  @doc "The question the tour types into the thread, and the answer it gets."
  def exchange do
    {"What is this paragraph actually doing?",
     """
     Two things, and the second one is quieter.

     It is placing the scene — where everyone is standing, and how long they have been
     standing there. And it is establishing that nobody in the room will say the thing
     out loud, which the rest of the section then depends on.

     The risk is that the second job is carried entirely by one clause. If a reader
     skims it, the next three pages read as people being oddly polite.

     *(A fixed example. The tour never calls the model, so this is not a reading of
     your paragraph.)*
     """}
  end
end
