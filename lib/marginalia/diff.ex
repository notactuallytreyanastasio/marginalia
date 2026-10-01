defmodule Marginalia.Diff do
  @moduledoc """
  Two versions of a draft, aligned into rows a reader can put side by side.

  Paragraph granularity, not line. A line diff is right for code, where a
  line is a unit somebody wrote on purpose; prose here is one paragraph per
  line, and a line diff of it marks a whole 300-word paragraph changed
  because a comma moved. So paragraphs are the unit, and a paragraph that
  changed carries a word-level diff *inside* it — which is where the actual
  edit is visible.

  Rows come back as:

    * `{:same, left, right}` — unchanged, both sides present
    * `{:change, left, right}` — same position, different text
    * `{:del, left}` — removed
    * `{:ins, right}` — added

  The alignment is a longest-common-subsequence over paragraphs, so a
  paragraph inserted in the middle shifts nothing after it — which is the
  whole reason not to zip the two lists and compare position by position.

  The splitting, alignment and pairing are written in Temper
  (`temper/marginalia-core/src/diff.temper.md`) and generated into
  `Temper.MarginaliaCore`; this module turns its rows into the tuples the
  rest of the app matches on.
  """

  alias Temper.MarginaliaCore, as: Core

  @doc "Split prose into the paragraphs the diff aligns."
  def paragraphs(nil), do: []
  def paragraphs(text) when is_binary(text), do: text |> Core.paragraphs() |> Enum.to_list()

  @doc """
  Align two versions into rows.

  `{:change, _, _}` rather than a delete followed by an insert when a
  paragraph is recognisably the same one edited. Without that test, an edit
  to one sentence reads as a paragraph thrown away and a different one
  written, and the side-by-side loses the only thing it was for.
  """
  def rows(before_text, after_text) do
    Core.rows(before_text || "", after_text || "") |> Enum.map(&row/1)
  end

  defp row(%Core.Row{kind: "same", left: l, right: r}), do: {:same, l, r}
  defp row(%Core.Row{kind: "change", left: l, right: r}), do: {:change, l, r}
  defp row(%Core.Row{kind: "del", left: l}), do: {:del, l}
  defp row(%Core.Row{kind: "ins", right: r}), do: {:ins, r}

  @doc """
  A word-level diff of one changed pair, as `[{:same | :del | :ins, text}]`.

  The same shape `Marginalia.Rewrite.diff/2` returns, and for the same
  reason: it is what a template can render without deciding anything.
  """
  def words(left, right), do: Marginalia.Rewrite.diff(left, right)

  @doc "How many paragraphs were added, removed and edited."
  def stat(rows) do
    Enum.reduce(rows, %{same: 0, changed: 0, added: 0, removed: 0}, fn
      {:same, _, _}, acc -> Map.update!(acc, :same, &(&1 + 1))
      {:change, _, _}, acc -> Map.update!(acc, :changed, &(&1 + 1))
      {:ins, _}, acc -> Map.update!(acc, :added, &(&1 + 1))
      {:del, _}, acc -> Map.update!(acc, :removed, &(&1 + 1))
    end)
  end

  @doc "Whether anything at all differs."
  def any?(rows), do: Enum.any?(rows, &(not match?({:same, _, _}, &1)))
end
