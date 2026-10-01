# Old Works.Segmenter.split against the Temper port, on random manuscripts
# built to hit every strategy and threshold. Any difference fails the run.
# The old fixture carries the em-dash marker fix, the one intentional change.
Code.require_file(Path.join(__DIR__, "old_sentences.exs"))
Code.require_file(Path.join(__DIR__, "old_segmenter.exs"))
:rand.seed(:exsss, {String.to_integer(System.get_env("SEED", "1")), 3, 7})
pick = fn l -> Enum.at(l, :rand.uniform(length(l)) - 1) end

words = ["the", "kettle", "went", "cold.", "Nobody", "noticed", "until", "morning,", "when", "Ann", "found",
  "it", "beside", "a", "letter", "from", "Élodie.", "**Bold**", "_soft_", "`code`", "Mr.", "Smith", "42",
  "arrived;", "e.g.", "this."]

para = fn n -> Enum.map_join(1..n, " ", fn _ -> pick.(words) end) end
prose = fn max_words ->
  Stream.repeatedly(fn -> para.(5 + :rand.uniform(120)) end)
  |> Enum.reduce_while({[], 0}, fn p, {acc, w} ->
    w2 = w + length(String.split(p))
    if w2 > max_words, do: {:halt, {acc, w}}, else: {:cont, {[p | acc], w2}}
  end)
  |> elem(0)
  |> Enum.join(pick.(["\n\n", "\n\n\n\n", "\n \n", "\r\n\r\n"]))
end

markers = [
  "Chapter 7", "CHAPTER VII", "Part Two", "PART TWO: The Fall", "Book 3 — Ending", "Act ii",
  "Section 12. On " <> String.duplicate("é", 34), "Section 12. On " <> String.duplicate("é", 36),
  "VII.", "iv. A Title", "* * *", "*  *  *", "---", "------ break", "———", "——— Interlude",
  "chapters 1", "Chapter " <> String.duplicate("x", 95), "Opening words that are not a marker"
]

doc = fn ->
  size = pick.([200, 900, 2500, 6000, 12_000])
  case :rand.uniform(5) do
    1 -> ""
    2 ->
      Enum.map_join(1..(1 + :rand.uniform(5)), "\n", fn _ ->
        pick.(["# ", "## ", "### ", "#### ", "#"]) <> pick.(["Intro", "Rebuttal", "Ünder", ""]) <> "\n" <> prose.(div(size, 3))
      end)
    3 ->
      prose.(:rand.uniform(400)) <> "\n" <>
        Enum.map_join(1..(1 + :rand.uniform(5)), "\n", fn _ -> pick.(markers) <> "\n" <> prose.(div(size, 3)) end)
    _ -> pick.(["", "  ", "\r"]) <> prose.(size)
  end
end

new_split = fn t -> Temper.MarginaliaCore.segment(t) |> Enum.map(fn s -> %{title: s.title, body: s.body} end) end

n = String.to_integer(System.get_env("N", "300"))
stats = :counters.new(5, [])
for _ <- 1..n do
  t = doc.()
  {o, x} = {Old.Segmenter.split(t), new_split.(t)}
  titles = Enum.map(o, & &1.title)
  cond do
    o == [] -> :ok
    Enum.any?(titles, &String.starts_with?(&1, "Section ")) or Enum.any?(titles, &Regex.match?(~r/^\d+\. /, &1)) -> :counters.add(stats, 3, 1)
    Enum.any?(titles, &Regex.match?(~r/chapter|part|book|act|section|\*|---|^[ivxlc]+\./i, &1)) -> :counters.add(stats, 2, 1)
    true -> :counters.add(stats, 1, 1)
  end
  if Enum.any?(titles, &String.contains?(&1, "/")), do: :counters.add(stats, 4, 1)
  if String.contains?(t, "———"), do: :counters.add(stats, 5, 1)
  if o != x do
    IO.puts("MISMATCH\n doc=#{inspect(String.slice(t, 0, 600))}\n old=#{inspect(Enum.map(o, & &1.title))}\n new=#{inspect(Enum.map(x, & &1.title))}")
    diff = Enum.zip(o, x) |> Enum.find(fn {a, b} -> a != b end)
    if diff, do: IO.puts(" first differing section:\n old=#{inspect(elem(diff, 0), printable_limit: 400)}\n new=#{inspect(elem(diff, 1), printable_limit: 400)}")
    System.halt(1)
  end
end
IO.puts("#{n} manuscripts: split identical (headings #{:counters.get(stats, 1)}, markers #{:counters.get(stats, 2)}, windows #{:counters.get(stats, 3)}, subdivided #{:counters.get(stats, 4)}, with a ——— line #{:counters.get(stats, 5)})")
