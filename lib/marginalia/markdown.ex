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

  @opts [
    extension: [
      strikethrough: true,
      table: true,
      autolink: true,
      tasklist: true,
      footnotes: true
    ],
    parse: [smart: false],
    render: [hardbreaks: true, unsafe: false],
    sanitize: MDEx.Document.default_sanitize_options()
  ]

  @doc """
  Markdown to safe HTML, ready for a template.

  Never raises: a reply that will not parse is shown as escaped plain text
  rather than costing the user the answer.
  """
  def to_html(nil), do: Phoenix.HTML.raw("")
  def to_html(""), do: Phoenix.HTML.raw("")

  def to_html(text) when is_binary(text) do
    case MDEx.to_html(text, @opts) do
      {:ok, html} -> Phoenix.HTML.raw(html)
      _ -> Phoenix.HTML.html_escape(text)
    end
  rescue
    _ -> Phoenix.HTML.html_escape(text)
  end

  def to_html(other), do: Phoenix.HTML.html_escape(to_string(other))
end
