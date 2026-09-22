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
end
