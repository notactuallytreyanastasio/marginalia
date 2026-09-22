defmodule Marginalia.Markdown do
  @moduledoc """
  Model replies, rendered as markdown.

  The model writes markdown whether or not anyone asked it to — lists, bold,
  the occasional heading — so rendering it is not a nicety, it is the
  difference between a reply you can read and a wall of text.

  Sanitising is on. A reply is the model's prose plus spans quoted out of a
  manuscript, and neither has any business emitting a `<script>`; MDEx runs
  the output through ammonia, which strips tags and attributes by allowlist
  rather than by pattern, so a `javascript:` href or an `onerror` goes too.
  """

  @extension [
    strikethrough: true,
    table: true,
    autolink: true,
    tasklist: true,
    footnotes: true
  ]

  defp opts(breaks) do
    [
      extension: @extension,
      parse: [smart: false],
      render: [hardbreaks: breaks == :hard, unsafe: false],
      sanitize: MDEx.Document.default_sanitize_options()
    ]
  end

  @doc """
  Markdown to safe HTML, ready for a template.

  `breaks: :hard`, the default, turns every newline into a `<br>`. That is
  right for a model reply, where a line break is something the model chose.
  It is wrong for a draft, which is stored one sentence per line (see
  `Marginalia.Works.Sentences`) and, before that rule, arrived hard-wrapped
  at eighty columns from whatever editor it was written in. A draft is
  rendered with `breaks: :soft`, so a newline inside a paragraph is a space
  and the only breaks on the page are the ones the writer made with a blank
  line. That is what every other markdown renderer does with prose.

  Never raises: a reply that will not parse is shown as escaped plain text
  rather than costing the user the answer.
  """
  def to_html(text, opts \\ [])
  def to_html(nil, _opts), do: Phoenix.HTML.raw("")
  def to_html("", _opts), do: Phoenix.HTML.raw("")

  def to_html(text, opts) when is_binary(text) do
    case MDEx.to_html(text, opts(Keyword.get(opts, :breaks, :hard))) do
      {:ok, html} -> Phoenix.HTML.raw(html)
      _ -> Phoenix.HTML.html_escape(text)
    end
  rescue
    _ -> Phoenix.HTML.html_escape(text)
  end

  def to_html(other, _opts), do: Phoenix.HTML.html_escape(to_string(other))
end
