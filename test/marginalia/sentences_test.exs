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
end
