defmodule Marginalia.MarkdownTest do
  use ExUnit.Case, async: true
  alias Marginalia.Markdown

  test "a reply keeps its line breaks" do
    {:safe, html} = Markdown.to_html("one\ntwo")
    assert IO.iodata_to_binary(html) =~ "<br"
  end

  test "a draft joins the sentences of a paragraph and keeps its paragraphs" do
    {:safe, html} = Markdown.to_html("One.\nTwo.\n\nThree.", breaks: :soft)
    html = IO.iodata_to_binary(html)
    refute html =~ "<br"
    assert html =~ "<p>One.\nTwo.</p>"
    assert html =~ "<p>Three.</p>"
  end
end
