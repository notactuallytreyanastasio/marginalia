defmodule Marginalia.ReadingRenderTest do
  @moduledoc """
  A draft is stored one sentence per line. On the page, a paragraph is a
  paragraph: its sentences run on from one another, and only a blank line
  in the draft makes a break.
  """
  use ExUnit.Case, async: true
  alias Marginalia.Reading

  test "sentences on separate lines render as one paragraph" do
    {:safe, html} = Reading.render_block("One sentence.\nAnother sentence.\nA third.", nil, 1)
    html = IO.iodata_to_binary(html)
    refute html =~ "<br"
    assert html =~ "<p>One sentence.\nAnother sentence.\nA third.</p>"
  end

  test "a blank line in the draft is a paragraph break, and the highlight survives" do
    blocks = Reading.split("One.\nTwo.\n\nThree.\nFour.")
    assert blocks == ["One.\nTwo.", "Three.\nFour."]

    {:safe, html} = Reading.render_block("Three.\nFour.", "Four.", 2)
    html = IO.iodata_to_binary(html)
    assert html =~ ~s(<mark id="anchor-2">Four.</mark>)
    refute html =~ "<br"
  end

  test "emphasis that opens on one sentence line and closes on the next still pairs" do
    {:safe, html} = Reading.render_block("This is *very\nimportant* indeed.", nil, 3)
    assert IO.iodata_to_binary(html) =~ "<em>very\nimportant</em>"
  end

  test "a fenced block keeps every newline, soft breaks or not" do
    {:safe, html} = Reading.render_block("```\na. B.\n\nc. D.\n```", nil, 4)
    assert IO.iodata_to_binary(html) =~ "<code>a. B.\n\nc. D.\n</code>"
  end

  test "a rewrite preview whose original spans a sentence break still diffs in place" do
    text = "One sentence.\nAnother sentence.\nA third."
    preview = %{original: "sentence.\nAnother sentence.", text: "sentence.\nA second sentence."}
    {:safe, html} = Reading.render_block(text, nil, 5, preview)
    html = IO.iodata_to_binary(html)
    assert html =~ "<del class=\"mg-cut\">"
    assert html =~ "<ins class=\"mg-swap\">"
    refute html =~ "<br"
  end

  test "a highlight that starts on one line and ends on the next is one mark" do
    {:safe, html} = Reading.render_block("One.\nTwo.\nThree.", "Two.\nThree.", 6)
    html = IO.iodata_to_binary(html)
    assert html =~ ~s(<mark id="anchor-6">Two.\nThree.</mark>)
  end
end
