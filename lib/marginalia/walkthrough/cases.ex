defmodule Marginalia.Walkthrough.Cases do
  @moduledoc """
  The run through a Supreme Court term, across the three views it lives in.

  `Marginalia.Walkthrough` tours one page of somebody's own manuscript and
  has to fake the model to do it safely. This one has nothing to fake:
  every case is public record, already read, already related, and the
  tour's whole job is to show a reader what is in front of them. So the
  steps here press real controls against real documents, and nothing is
  stubbed.

  It runs in three legs, because the thing being explained is not a page:

    1. `/cases` — what the site is, and that a case is read as one
       document against another rather than as a case.
    2. `/links/:id/read` — the pairwise reading, which is the heart of
       it: the second document follows the first and snaps to whatever it
       is answering.
    3. `/cases/:slug/read` — the same opinion with *every* other document
       in the margin at once, including other cases in the term.

  Each leg ends by hopping to the next, so the tour crosses pages the way
  a reader would. Any leg also stands alone: someone who arrives in the
  middle gets the steps for the view they are actually looking at.
  """

  @index [
    %{
      id: "hook",
      title: "One real disagreement, first",
      body:
        "Every case leads with the sharpest thing found between its documents, in the terms the pass used. Not a summary of the case — a place where two of its documents pull against each other.",
      target: ".cs-case:first-of-type .cs-hook",
      place: "bottom"
    },
    %{
      id: "held",
      title: "The holding is the Court's own sentence",
      body:
        "Quoted out of the opinion, not paraphrased, and not taken from the Reporter's syllabus — which is no part of the opinion and says so on its own first page. Three of these sixteen never state their holding in one sentence, and those show none at all.",
      target: ".cs-case:first-of-type .cs-held",
      place: "bottom"
    },
    %{
      id: "ways",
      title: "A case is read one document against another",
      body:
        "Not 'open the case'. The opinion against the dissent, the opinion against the advocate it is answering — each with how much the two actually have to say to each other, which is the honest signal of which to open.",
      target: ".cs-case:first-of-type .cs-ways",
      place: "top"
    },
    %{
      id: "kin",
      title: "And the term argues with itself",
      body:
        "Cases are related across the term too, chosen by the vocabulary the opinions actually share rather than by anyone's idea of a theme. It is the only thing here that could not have come from reading one case carefully.",
      target: ".cs-case:first-of-type .cs-kin",
      place: "top"
    },
    %{
      id: "sources",
      title: "Everything links back to the PDF",
      body:
        "The whole claim of this site is that none of it is invented. The only way to make that checkable is to keep the Court's own file one click away, so every document does.",
      target: ".cs-case:first-of-type .cs-parts",
      place: "top"
    },
    %{
      id: "into",
      title: "Now the reading itself",
      body:
        "This is where the site actually happens. Opening the strongest pairing in the first case.",
      target: ".cs-case:first-of-type .cs-ways li:first-child",
      place: "top",
      act: %{kind: "hop", to: "first_pair"}
    }
  ]

  @follow [
    %{
      id: "sides",
      title: "Left is read. Right is the reference",
      body:
        "One document down the left at your own pace. The other is dimmed on purpose — it lights up only where it has something to say about the passage you are on.",
      target: ".fl-colhead",
      place: "bottom"
    },
    %{
      id: "follow",
      title: "The right side follows you",
      body:
        "Scroll the left and the right is scrolled for you, snapping to the passage your paragraph is talking to. Stop following whenever you like: scroll the right yourself, read it, and the left picks you up again.",
      target: "#fl-lead",
      place: "right"
    },
    %{
      id: "wire",
      title: "The line runs through the reason",
      body:
        "Left passage, why, right passage — the actual shape of the claim. The middle is the reason for drawing it, and it belongs to neither document.",
      target: ".fl-mid",
      place: "left"
    },
    %{
      id: "filter",
      title: "One kind of relation at a time",
      body:
        "Tension leaves only where the two genuinely pull apart. Answers leaves where one replies to the other. The filter changes what the page is about, not how much of it there is.",
      target: ".fl-legend",
      place: "bottom",
      act: %{kind: "push", event: "set_only", params: %{"only" => "tension"}}
    },
    %{
      id: "filter_back",
      title: "Everything, again",
      body: "Back to the whole relationship, which is how it opens.",
      target: ".fl-legend",
      place: "bottom",
      act: %{kind: "push", event: "set_only", params: %{"only" => "all"}}
    },
    %{
      id: "gaps",
      title: "The quiet stretches are folded",
      body:
        "Where the two have nothing to say to each other, the prose is folded away with its size on the label. Nothing is deleted — open one and read it.",
      target: ".fl-gap",
      place: "right"
    },
    %{
      id: "chat",
      title: "You can argue with it",
      body:
        "Click the line between two passages and both go into the question. The chat starts fresh on this page and holds whatever you cite into it.",
      target: ".lc",
      place: "left"
    },
    %{
      id: "onward",
      title: "Two documents is the pair. Now the whole case",
      body: "The same opinion, with every other document in the case beside it at once.",
      target: ".fl-colhead",
      place: "bottom",
      act: %{kind: "hop", to: "case_read"}
    }
  ]

  @case_read [
    %{
      id: "margin",
      title: "The whole case in one margin",
      body:
        "The dissent and every advocate, against the same paragraph, each saying which one it is. Reading the pairs separately is exactly what this hides — and the paragraphs where all of them speak at once are the ones worth having.",
      target: ".cr-grid .cr-notes:not(.bare)",
      place: "left"
    },
    %{
      id: "row",
      title: "A paragraph and its notes are one row",
      body:
        "One hairline runs from the left edge of the paragraph, across the gutter, into its notes. They are level because the layout says so — there is no scrolling machinery here to drift.",
      target: ".cr-text.linked",
      place: "right"
    },
    %{
      id: "who",
      title: "Filter by who is speaking",
      body:
        "Each chip is one of the other documents, with how often it has something to say. A dashed chip is another case in the term rather than another document in this one.",
      target: ".cr-srcs",
      place: "bottom"
    },
    %{
      id: "lead",
      title: "Read it from anyone's side",
      body:
        "Any document in the case can be the one you read. The dissent with the majority in its margin is a different experience from the reverse, and both of them are the case.",
      target: ".cr-pick",
      place: "bottom",
      act: %{kind: "click", target: ".cr-pick > summary"}
    },
    %{
      id: "done",
      title: "That is the whole of it",
      body:
        "Sixteen cases, eighty-two documents, each read on its own and then related. Every connection is anchored to a sentence in both documents, and anything that could not be found in both was discarded before it was stored.",
      target: nil,
      place: "centre"
    }
  ]

  @doc "The steps for a view, or `[]` if it has no leg of the tour."
  def steps(:cases), do: @index
  def steps(:follow), do: @follow
  def steps(:case_read), do: @case_read
  def steps(_view), do: []

  @doc "Whether a view has a leg of this tour."
  def for_view?(view), do: steps(view) != []
end
