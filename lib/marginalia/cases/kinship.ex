defmodule Marginalia.Cases.Kinship do
  @moduledoc """
  Which cases are about the same thing as which other cases.

  Inside a case the pairings are obvious — the opinion, what dissents from
  it, who argued it. Across a term they are not, and they are the more
  interesting relationship: the Court deciding executive power in one case
  and citizenship in another is the same nine people reasoning twice, and
  the places those two readings touch is a thing no table of contents
  shows.

  Picking those pairs by hand would mean asserting a theme, which is
  exactly the kind of claim this product refuses to make without evidence.
  So the documents choose their own kin: each opinion becomes the bag of
  terms its own read pass used — the titles and bodies of its nodes, and
  the first impression — and pairs are scored on the distinctive terms
  they share.

  Distinctive is doing the work. "Court", "held" and "statute" are in
  everything and carry nothing; a term in one document alone cannot be
  shared. What survives is the middle: `removal`, `jurisdiction`,
  `sovereign`, `warrant` — the words that tell two cases apart from the
  other fourteen and put them together with each other.

  Nothing here calls a model. The pairs it proposes are then read by the
  linker like any other pair, and an edge that cannot be anchored in both
  documents is thrown away exactly as it would be inside a case.
  """

  @stop ~w(
    about above after again against all also and any are because been before
    being below between both but cannot could did does doing down during each
    few for from further had has have having her here hers him his how into
    its itself more most nor not now off once only other ought our out over
    own same she should some such than that the their them then there these
    they this those through too under until very was were what when where
    which while who whom why will with would you your
    court courts case cases opinion opinions held holding justice justices
    argument arguments dissent dissents concurrence majority
    section sections paragraph draft manuscript reader writing writes
    argues argued argue claims claim point points question questions
    says said say reads read whether because therefore however
  )

  # a term in fewer than two documents is nobody's kin; a term in more than
  # this share of them is furniture
  @min_df 2
  @max_share 0.33
  @min_len 5

  # A word used once is a word that happened; a word used twice is a word
  # the document is about. Without this the score was dominated by the
  # long tail, and the longest document came out as everyone's closest
  # relation — it simply had more chances to coincide.
  @min_tf 2

  @doc """
  The strongest pairs across collections, best first.

  `works` is one document per case — the opinion, normally. Each needs
  `:id`, `:collection` and its nodes already loaded by `terms_for/1`.
  """
  def pairs(bags, limit \\ 12) do
    n = map_size(bags)
    df = document_frequency(bags)
    max_df = max(trunc(n * @max_share), @min_df)

    keep =
      df
      |> Enum.filter(fn {_t, c} -> c >= @min_df and c <= max_df end)
      |> Map.new(fn {t, c} -> {t, :math.log(n / c)} end)

    ids = bags |> Map.keys() |> Enum.sort()

    for a <- ids, b <- ids, a < b do
      shared =
        bags
        |> Map.fetch!(a)
        |> MapSet.intersection(Map.fetch!(bags, b))
        |> Enum.filter(&Map.has_key?(keep, &1))

      weight = shared |> Enum.map(&Map.fetch!(keep, &1)) |> Enum.sum()

      # long documents share more of everything; divide it out properly,
      # or the biggest document is everyone's nearest kin
      size = :math.sqrt(MapSet.size(Map.fetch!(bags, a)) * MapSet.size(Map.fetch!(bags, b)))

      %{
        a: a,
        b: b,
        score: if(size > 0, do: weight / size, else: 0.0),
        shared: shared |> Enum.sort_by(&(-Map.fetch!(keep, &1))) |> Enum.take(8)
      }
    end
    |> Enum.reject(&(&1.score == 0.0))
    |> Enum.sort_by(&(-&1.score))
    |> Enum.take(limit)
  end

  defp document_frequency(bags) do
    Enum.reduce(bags, %{}, fn {_id, set}, acc ->
      Enum.reduce(set, acc, fn term, acc -> Map.update(acc, term, 1, &(&1 + 1)) end)
    end)
  end

  @doc """
  The bag of terms a document's own reading used.

  The nodes rather than the prose: the read pass has already said what
  each passage is doing, in language it uses consistently across every
  document, which is a far better basis for comparison than two judges'
  prose styles.
  """
  def terms(text_parts) do
    text_parts
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\s]+/u, " ")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&singular/1)
    |> Enum.reject(&(String.length(&1) < @min_len or &1 in @stop))
    |> Enum.frequencies()
    |> Enum.filter(fn {_t, n} -> n >= @min_tf end)
    |> MapSet.new(fn {t, _n} -> t end)
  end

  # "warrants" and "warrant" are the same word for this purpose, and a
  # stemmer is more machinery than the difference is worth
  defp singular(word) do
    cond do
      String.ends_with?(word, "ies") and String.length(word) > 5 ->
        String.slice(word, 0..-4//1) <> "y"

      String.ends_with?(word, "sses") ->
        String.slice(word, 0..-3//1)

      String.ends_with?(word, "s") and not String.ends_with?(word, "ss") ->
        String.slice(word, 0..-2//1)

      true ->
        word
    end
  end
end
