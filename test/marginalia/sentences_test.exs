defmodule Marginalia.Works.SentencesTest do
  @moduledoc """
  Prose is stored one sentence per line. The property worth asserting is
  the one the diff view and every outside diff rests on: the only line
  breaks inside a paragraph are sentence ends, and blocks that are not
  prose are byte for byte what they were.
  """
  use ExUnit.Case, async: true
  alias Marginalia.Works.Sentences

  test "a hard-wrapped paragraph comes back one sentence per line" do
    wrapped =
      "At 04:47 UTC on 22 September 2026, agent-7 implemented the Guideline step\n" <>
        "reset for lock delay. The idea came from agent-8, which had not committed the\n" <>
        "code. Agent-8 had logged a decision."

    assert Sentences.reflow(wrapped) ==
             "At 04:47 UTC on 22 September 2026, agent-7 implemented the Guideline step reset for lock delay.\n" <>
               "The idea came from agent-8, which had not committed the code.\n" <>
               "Agent-8 had logged a decision."
  end

  test "paragraphs stay separated by a blank line" do
    text = "One. Two.\n\nThree. Four."
    assert Sentences.reflow(text) == "One.\nTwo.\n\nThree.\nFour."
  end

  test "reflowing twice changes nothing" do
    once =
      Sentences.reflow("She stood at the window\nfor an hour. The kettle went cold. It was late.")

    assert Sentences.reflow(once) == once
  end

  test "abbreviations and initials do not end a sentence" do
    text = "Ask Dr. Jones, e.g. tomorrow. J. K. Rowling agreed. It cost No. 4 dearly. Done."

    assert Sentences.reflow(text) ==
             "Ask Dr. Jones, e.g. tomorrow.\nJ. K. Rowling agreed.\nIt cost No. 4 dearly.\nDone."
  end

  test "a period followed by a lowercase word is not a boundary" do
    text = "The file is game.js and it runs. agent-8 logged it. Then it ran."

    assert Sentences.reflow(text) ==
             "The file is game.js and it runs. agent-8 logged it.\nThen it ran."
  end

  test "decimals, question marks, exclamations and closing quotes" do
    text = ~s(It scored 3.16 on the board! Was that enough? "No," she said. "Not nearly." Fine.)

    assert Sentences.reflow(text) ==
             ~s(It scored 3.16 on the board!\nWas that enough?\n"No," she said.\n"Not nearly."\nFine.)
  end

  test "fenced code is untouched, blank lines and all" do
    code = "```\nfoo. Bar baz.\n\nqux. Quux.\n```"

    assert Sentences.reflow("Intro one. Intro two.\n\n" <> code) ==
             "Intro one.\nIntro two.\n\n" <> code
  end

  test "headings, tables, lists, indented code and rules are untouched" do
    blocks = [
      "## A heading. With a period. And More.",
      "| a. B | c. D |\n|---|---|\n| e. F | g. H |",
      "- one. Two.\n- three. Four.",
      "1. first. Second.\n2. third. Fourth.",
      "    code. More code.\n    still code. Yes.",
      "---"
    ]

    for b <- blocks, do: assert(Sentences.reflow(b) == b)
  end

  test "a blockquote is reflowed and keeps its prefix" do
    q =
      "> agent-8 logged that the cap locks a piece. Agent-7 read it. It\n> wrote its own version."

    assert Sentences.reflow(q) ==
             "> agent-8 logged that the cap locks a piece.\n> Agent-7 read it.\n> It wrote its own version."
  end

  test "html blocks are untouched" do
    html = "<div class=\"x\">one. Two.\nthree.</div>"
    assert Sentences.reflow(html) == html
  end

  test "markdown emphasis at the start of a sentence still starts one" do
    text = "This is bold. **Really** bold. `Code` too. `code` is not a start."

    assert Sentences.reflow(text) ==
             "This is bold.\n**Really** bold.\n`Code` too. `code` is not a start."
  end

  # --- edges of the boundary rule -------------------------------------------

  test "curly quotes, parentheses and brackets close a sentence" do
    text = ~s|He said “stop.” Then he left (for good.) Fine [really.] Done.|

    assert Sentences.reflow(text) ==
             ~s|He said “stop.”\nThen he left (for good.)\nFine [really.]\nDone.|
  end

  test "an ellipsis ends a sentence only when a sentence follows" do
    assert Sentences.reflow("Wait... What? Wait... and then. End.") ==
             "Wait...\nWhat?\nWait... and then.\nEnd."
  end

  test "a sentence can start with a digit, a link or an opening quote" do
    text =
      ~s|It was late. 2026 was the year. [Deciduous](https://deciduous.dev) records it. "Yes," she said.|

    assert Sentences.reflow(text) ==
             ~s|It was late.\n2026 was the year.\n[Deciduous](https://deciduous.dev) records it.\n"Yes," she said.|
  end

  test "capitals outside ASCII start sentences too" do
    assert Sentences.reflow("Élan vital. Über alles. Ça va.") ==
             "Élan vital.\nÜber alles.\nÇa va."
  end

  test "more abbreviations that are not sentence ends" do
    text = "See Fig. 3 and cf. the table. Mrs. Smith vs. Mr. Jones, Inc. won. Prof. Lee agreed."

    assert Sentences.reflow(text) ==
             "See Fig. 3 and cf. the table.\nMrs. Smith vs. Mr. Jones, Inc. won.\nProf. Lee agreed."
  end

  test "a one-sentence paragraph is one line" do
    text = "A single sentence, wrapped\nby an editor at seventy\ncolumns, is one line"

    assert Sentences.reflow(text) ==
             "A single sentence, wrapped by an editor at seventy columns, is one line"
  end

  test "runs of spaces, tabs and ragged indentation collapse to one space" do
    text = "One   sentence,\t\tspaced.\n   Another,\n\t indented. "
    assert Sentences.reflow(text) == "One sentence, spaced.\nAnother, indented."
  end

  test "windows line endings are absorbed" do
    assert Sentences.reflow("One. Two\r\nthree.\r\n\r\nFour.") == "One.\nTwo three.\n\nFour."
  end

  test "a period inside a word or a version number is not a boundary" do
    text = "Use v1.2 of game.js today. Elixir 1.19.5 works. Done."
    assert Sentences.reflow(text) == "Use v1.2 of game.js today.\nElixir 1.19.5 works.\nDone."
  end

  # --- blocks that must come back untouched, or nearly ----------------------

  test "a blockquote keeps its own paragraph breaks" do
    q = "> First. Second.\n>\n> Third. Fourth."
    assert Sentences.reflow(q) == "> First.\n> Second.\n>\n> Third.\n> Fourth."
  end

  test "a setext heading is not joined to its underline" do
    assert Sentences.reflow("A title. With a period.\n=====") == "A title. With a period.\n====="
    assert Sentences.reflow("Sub. Title.\n---") == "Sub. Title.\n---"
  end

  test "a table with no leading pipes is untouched" do
    t = "a. B | c. D\n---|---\ne. F | g. H"
    assert Sentences.reflow(t) == t
  end

  test "a fenced block with a tilde fence and an info string is untouched" do
    code = "~~~elixir\nx = 1. y = 2.\n\nz. Z.\n~~~"
    assert Sentences.reflow(code) == code
  end

  test "an image or link on a line of its own is untouched" do
    assert Sentences.reflow("![alt text. More.](img.png)") == "![alt text. More.](img.png)"
  end

  test "nothing, nil and whitespace come back as nothing" do
    assert Sentences.reflow(nil) == nil
    assert Sentences.reflow("") == ""
    assert Sentences.reflow("   \n\n  ") == ""
  end

  test "a mixed document: only the prose moves" do
    doc =
      "# Title\n\nIntro one. Intro two.\n\n- item one. Still one.\n- item two.\n\n" <>
        "```\ncode. Code.\n```\n\n> Quoted one. Quoted two.\n\nOutro one. Outro\ntwo."

    assert Sentences.reflow(doc) ==
             "# Title\n\nIntro one.\nIntro two.\n\n- item one. Still one.\n- item two.\n\n" <>
               "```\ncode. Code.\n```\n\n> Quoted one.\n> Quoted two.\n\nOutro one.\nOutro two."
  end

  test "reflowing the mixed document twice changes nothing" do
    doc = "Intro one. Intro two.\n\n- item one.\n\n> Quoted one. Quoted two.\n\nOutro."
    once = Sentences.reflow(doc)
    assert Sentences.reflow(once) == once
  end
end
