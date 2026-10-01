# Marginalia.Diff and Marginalia.Rewrite.diff/2, as they were in Elixir before the Temper port (main at
# c9eb474), renamed under Old.* so temper/verify can run them beside the
# generated Temper.MarginaliaCore. Kept verbatim except for the rename.
defmodule Old.Diff do
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
  """

  @doc "Split prose into the paragraphs the diff aligns."
  def paragraphs(nil), do: []

  def paragraphs(text) when is_binary(text) do
    text
    |> String.replace("\r\n", "\n")
    |> String.split(~r/\n{2,}/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  @doc """
  Align two versions into rows.

  `{:change, _, _}` rather than a delete followed by an insert when a
  paragraph is recognisably the same one edited. Without that test, an edit
  to one sentence reads as a paragraph thrown away and a different one
  written, and the side-by-side loses the only thing it was for.
  """
  def rows(before_text, after_text) do
    a = paragraphs(before_text)
    b = paragraphs(after_text)

    a
    |> lcs(b)
    |> pair()
  end

  # Runs of deletes immediately followed by inserts are the interesting case:
  # in prose that is almost always an edit, not a removal and an unrelated
  # addition. Pairing them positionally within the run is what makes the two
  # columns line up.
  defp pair(ops), do: pair(ops, [])

  defp pair([], acc), do: Enum.reverse(acc)

  defp pair([{:same, p} | rest], acc), do: pair(rest, [{:same, p, p} | acc])

  # A whole run of non-matching ops, in whatever order the walk emitted them.
  # It emits inserts before deletes, so splitting on `{:del, _}` first saw a
  # run of one and paired nothing — an edited paragraph came out as an insert
  # and a delete, which is the one thing the side-by-side exists to avoid.
  defp pair(ops, acc) do
    {run, rest} = Enum.split_while(ops, &(not match?({:same, _}, &1)))

    dels = for {:del, p} <- run, do: p
    ins = for {:ins, p} <- run, do: p

    acc =
      Enum.reduce(zip_longest(dels, ins), acc, fn
        {nil, r}, acc -> [{:ins, r} | acc]
        {l, nil}, acc -> [{:del, l} | acc]
        {l, r}, acc -> [{:change, l, r} | acc]
      end)

    pair(rest, acc)
  end

  defp zip_longest(a, b) do
    n = max(length(a), length(b))
    Enum.zip(pad(a, n), pad(b, n))
  end

  defp pad(list, n), do: list ++ List.duplicate(nil, n - length(list))

  @doc """
  A word-level diff of one changed pair, as `[{:same | :del | :ins, text}]`.

  The same shape `Marginalia.Rewrite.diff/2` returns, and for the same
  reason: it is what a template can render without deciding anything.
  """
  def words(left, right), do: Old.Rewrite.diff(left, right)

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

  # --- longest common subsequence over paragraphs ---------------------------
  #
  # Hashes rather than whole paragraphs in the table: these are 300-word
  # strings and the comparison happens O(n*m) times.

  defp lcs(a, b) do
    av = List.to_tuple(a)
    bv = List.to_tuple(b)
    ah = a |> Enum.map(&key/1) |> List.to_tuple()
    bh = b |> Enum.map(&key/1) |> List.to_tuple()

    n = tuple_size(av)
    m = tuple_size(bv)

    table = build(ah, bh, n, m)
    walk(av, bv, ah, bh, table, 0, 0, n, m, [])
  end

  # A paragraph's identity for alignment: whitespace-insensitive, because a
  # rewrap is not an edit.
  defp key(p), do: p |> String.replace(~r/\s+/, " ") |> String.trim()

  defp build(ah, bh, n, m) do
    for i <- n..0//-1, reduce: %{} do
      table ->
        for j <- m..0//-1, reduce: table do
          t ->
            value =
              cond do
                i == n or j == m -> 0
                elem(ah, i) == elem(bh, j) -> 1 + Map.fetch!(t, {i + 1, j + 1})
                true -> max(Map.fetch!(t, {i + 1, j}), Map.fetch!(t, {i, j + 1}))
              end

            Map.put(t, {i, j}, value)
        end
    end
  end

  defp walk(av, bv, ah, bh, table, i, j, n, m, acc) do
    cond do
      i >= n and j >= m ->
        Enum.reverse(acc)

      i < n and j < m and elem(ah, i) == elem(bh, j) ->
        walk(av, bv, ah, bh, table, i + 1, j + 1, n, m, [{:same, elem(av, i)} | acc])

      j < m and (i >= n or Map.fetch!(table, {i, j + 1}) >= Map.fetch!(table, {i + 1, j})) ->
        walk(av, bv, ah, bh, table, i, j + 1, n, m, [{:ins, elem(bv, j)} | acc])

      true ->
        walk(av, bv, ah, bh, table, i + 1, j, n, m, [{:del, elem(av, i)} | acc])
    end
  end
end

defmodule Old.Rewrite do
  @doc """
  A word-level diff of two spans, as `[{:same | :del | :ins, words}]`.

  Shown beside the candidate so the writer can see what actually changed
  rather than re-reading two similar sentences and hoping.
  """
  def diff(a, b) do
    aw = words(a)
    bw = words(b)
    ak = Enum.map(aw, &String.trim/1)
    bk = Enum.map(bw, &String.trim/1)

    if unrelated?(ak, bk) do
      merge(Enum.map(aw, &{:del, &1}) ++ Enum.map(bw, &{:ins, &1}))
    else
      ak
      |> List.myers_difference(bk)
      |> attach(aw, bw, [])
      |> merge()
    end
  end

  # Myers is linear when two texts are alike and quadratic when they share
  # nothing, and two long spans that share nothing is the one case where a
  # word diff says nothing anyway: every word deleted, every word inserted,
  # in alternating specks. Shown as one deletion and one insertion instead,
  # decided by vocabulary, which costs one pass over each side.
  @unrelated_from 200
  @unrelated_below 0.05

  defp unrelated?(ak, bk) when length(ak) >= @unrelated_from and length(bk) >= @unrelated_from do
    a = MapSet.new(ak)
    b = MapSet.new(bk)
    shared = MapSet.size(MapSet.intersection(a, b))
    shared < @unrelated_below * min(MapSet.size(a), MapSet.size(b))
  end

  defp unrelated?(_ak, _bk), do: false

  defp words(nil), do: []
  defp words(t), do: Regex.scan(~r/\S+\s*/, t) |> Enum.map(&hd/1)

  # `List.myers_difference/2` rather than a longest-common-subsequence table
  # of our own. The table was a Map with one entry per pair of words, built
  # bottom-up, and the spans it was written for are a sentence or two, where
  # that is nothing. The revision log then started diffing whole sections:
  # a 2,000-word section against its rewrite is four million Map writes,
  # about a second and a half each, and a draft with five such revisions
  # took thirteen seconds to render. LiveView renders twice, once for the
  # HTML and once when the socket connects, so the page never connected at
  # all. Myers is O((n+m)·d): the same twelve revisions take two hundred
  # milliseconds, and the result is just as deterministic.
  #
  # Myers compares the trimmed words, so a word is the same word whatever
  # whitespace followed it, and the whitespace each word actually carried
  # comes back from the original lists as the script is walked.
  defp attach([], _aw, _bw, acc), do: Enum.reverse(acc)

  # A shared word is rendered on both sides, so it has to carry whitespace
  # that is right for both. Take the new side's, and when the new side has
  # none, because the word ends its paragraph there, take the old side's:
  # otherwise the old side reads "word38only118" where two words met.
  defp attach([{:eq, ws} | rest], aw, bw, acc) do
    n = length(ws)
    {from_a, aw} = Enum.split(aw, n)
    {from_b, bw} = Enum.split(bw, n)

    acc =
      Enum.zip(from_a, from_b)
      |> Enum.reduce(acc, fn {ta, tb}, acc ->
        token = if String.trim_trailing(tb) == tb, do: String.trim(tb) <> trailing(ta), else: tb
        [{:same, token} | acc]
      end)

    attach(rest, aw, bw, acc)
  end

  defp attach([{:del, ws} | rest], aw, bw, acc) do
    {taken, aw} = Enum.split(aw, length(ws))
    attach(rest, aw, bw, Enum.reduce(taken, acc, &[{:del, &1} | &2]))
  end

  defp attach([{:ins, ws} | rest], aw, bw, acc) do
    {taken, bw} = Enum.split(bw, length(ws))
    attach(rest, aw, bw, Enum.reduce(taken, acc, &[{:ins, &1} | &2]))
  end

  defp trailing(token), do: String.slice(token, String.length(String.trim_trailing(token))..-1//1)

  defp merge(parts) do
    parts
    |> Enum.chunk_by(&elem(&1, 0))
    |> Enum.map(fn chunk ->
      {elem(hd(chunk), 0), chunk |> Enum.map(&elem(&1, 1)) |> Enum.join()}
    end)
  end
end
