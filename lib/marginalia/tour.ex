defmodule Marginalia.Tour do
  @moduledoc """
  What each tab is for, shown once the first time it is opened.

  Every one of these exists because the affordance it describes is invisible
  until someone tells you: a hairline in the gutter, a highlight you can
  hover, a filter that changes what the margin is about. A product that
  needs a manual has a problem, and a product with a genuinely quiet
  interface needs one sentence per surface — the fix for the first is not
  pretending the second does not apply.

  Deliberately short. Nobody reads the second paragraph of a tour.
  """

  @tours %{
    read: %{
      title: "The page, with its notes in the margin",
      points: [
        "Every note sits beside the sentence that caused it. The highlight is the span it is anchored to, copied from your draft character for character.",
        "Everything is on by default. Beats are what the draft does, in order; Connections and Tensions are what crosses sections. Each filter leaves only that kind in the margin.",
        "Click and hold, then drag across any passage to select it. Three things come up: talk about that spot, ask for rewrites of it, or carry it into the chat.",
        "Move the pointer to the left edge of a paragraph and a thin line appears in the margin. Click it to start a thread pinned to that paragraph, which will still be there when you come back."
      ]
    },
    graph: %{
      title: "What leads to what",
      points: [
        "Every row is one move the draft makes. Hover a row and the panel on the right fills in with what it says — move down the list and read the whole draft without clicking anything.",
        "Click a row to keep it there. The panel then holds its type, the section it came from, your own sentence underneath it, and every node it follows from or leads to. Hovering something else only previews; the one you clicked comes back when you move away.",
        "A filled dot is anchored to a line in your draft. A hollow one is structural — the model's word for a move, with no single sentence behind it.",
        "Solid lines are the chain running down the page. Dotted ones cross sections: develops, pays off, requires, tension.",
        "Build decision graph runs the deciduous method over the whole draft — narratives first, then a goal / option / decision / action chain for each. It takes a few minutes and the Trace tab shows it happening."
      ]
    },
    spine: %{
      title: "The whole draft at once",
      points: [
        "The first impression is what a reader takes away, written before any of the detail.",
        "The spine is the chain everything hangs off. Each node shows where it actually happens, with your own words under it.",
        "Discuss opens the chat already holding that node and every section it touches, so you never re-explain which one you meant.",
        "The questions at the bottom each name something specific. They are attached to their paragraphs on the page."
      ]
    },
    threads: %{
      title: "What runs across sections",
      points: [
        "A thread is a pattern that spans the draft rather than happening in one place — carried, thin, or dropped.",
        "A dropped thread is usually the most useful thing on this page: something set up and never paid off.",
        "Each shows the beats it runs through. Discuss carries the whole lot into the chat."
      ]
    },
    trace: %{
      title: "What the model actually did",
      points: [
        "Every tool call made while building the graph, and what the server answered.",
        "The refusals are the point: a quote that was not in your draft, or a link that broke the flow rule. They are kept rather than hidden.",
        "It fills in live while a build runs."
      ]
    },
    prompts: %{
      title: "Every prompt, read out of the running code",
      points: [
        "Not retyped here — read from the modules that ran, so this page cannot drift from what actually happened.",
        "Each pass says which model it used and what it produces.",
        "The chat's three stances are at the bottom."
      ]
    }
  }

  @doc "The tour for a view, or nil."
  def for_view(view) when is_atom(view), do: Map.get(@tours, view)
  def for_view(_), do: nil

  @doc "Every view that has one, as strings — what gets stored as seen."
  def views, do: @tours |> Map.keys() |> Enum.map(&Atom.to_string/1)
end
