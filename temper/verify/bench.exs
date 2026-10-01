# The Elixir each port replaced against the generated code, on realistic
# sizes: median microseconds of 15 runs each. Run by bin/temper-verify bench.
for f <- ~w(old_diff old_sentences old_reflow old_segmenter), do: Code.require_file(Path.join(__DIR__, "#{f}.exs"))
:rand.seed(:exsss, {1, 2, 3})
pick = fn l -> Enum.at(l, :rand.uniform(length(l)) - 1) end

prose_words =
  Path.wildcard(Path.join(__DIR__, "../../lib/**/*.ex"))
  |> Enum.flat_map(fn f -> Regex.scan(~r/@moduledoc """\n(.*?)"""/s, File.read!(f), capture: :all_but_first) end)
  |> List.flatten() |> Enum.join(" ") |> String.split(~r/\s+/, trim: true)

words = fn n -> Enum.map_join(1..n, " ", fn _ -> pick.(prose_words) end) end
edit = fn text -> text |> String.split(" ") |> Enum.map(fn w -> if :rand.uniform(25) == 1, do: pick.(prose_words), else: w end) |> Enum.join(" ") end
paras = fn n, size -> Enum.map_join(1..n, "\n\n", fn _ -> words.(size) end) end

section = words.(2000)
doc = paras.(60, 90)
page = Enum.map_join(1..400, "\n", fn _ -> words.(12) <> if(:rand.uniform(8) == 1, do: " capaci-", else: "") end)
manuscript = paras.(130, 90)

time = fn f ->
  for(_ <- 1..15, do: elem(:timer.tc(f), 0)) |> Enum.sort() |> Enum.at(7)
end

rows = [
  {"word diff, 2,000-word section, 4% edited", fn -> Old.Rewrite.diff(section, edit.(section)) end,
   fn -> Temper.MarginaliaCore.diff(section, edit.(section)) end},
  {"paragraph diff, 60 paragraphs", fn -> Old.Diff.rows(doc, edit.(doc)) end,
   fn -> Temper.MarginaliaCore.rows(doc, edit.(doc)) end},
  {"sentences reflow, 5,400 words", fn -> Old.Sentences.reflow(doc) end, fn -> Temper.MarginaliaCore.reflow(doc) end},
  {"PDF page reflow, 400 lines", fn -> Old.Reflow.reflow(page) end, fn -> Temper.MarginaliaCore.reflowPage(page) end},
  {"segmenter, 11,700-word manuscript", fn -> Old.Segmenter.split(manuscript) end,
   fn -> Temper.MarginaliaCore.segment(manuscript) end}
]

IO.puts(String.pad_trailing("", 42) <> String.pad_leading("Elixir", 10) <> String.pad_leading("Temper", 10) <> "   ratio")
for {label, old, new} <- rows do
  {o, n} = {time.(old), time.(new)}
  IO.puts(String.pad_trailing(label, 42) <> String.pad_leading("#{div(o, 1000)} ms", 10) <> String.pad_leading("#{div(n, 1000)} ms", 10) <> "   #{Float.round(n / max(o, 1), 1)}x")
end
