# Old (Reading.split, Sentences.reflow/reflow_block) against the Temper port,
# on random markdown built to hit every rule. Any difference fails the run.
Code.require_file(Path.join(__DIR__, "old_sentences.exs"))
:rand.seed(:exsss, {String.to_integer(System.get_env("SEED", "1")), 5, 8})
pick = fn l -> Enum.at(l, :rand.uniform(length(l)) - 1) end

words = ~w(the kettle went cold and nobody noticed until morning when Ann found it
  still there beside a letter from Élodie Łukasz Ωmega ٣ apples 42 ok see Smith)
abbrevs = ~w(e.g. i.e. vs. etc. cf. viz. ca. Mr. Mrs. Ms. Dr. Prof. St. No. Fig. Jr. Sr. Inc. Ltd. Co. J. K. A. x. q.)
ends = [".", "!", "?", ".\"", ".”", "?’", ".)", "!]", "...", ".'"]
opens = ["", "", "", "\"", "“", "‘", "(", "[", "*", "_", "`", "**"]
spaces = [" ", " ", " ", "  ", "\t", " ", " ", " \n", "\n", "\r\n"]

sentence = fn ->
  n = :rand.uniform(9)
  body = for _ <- 1..n, do: (if :rand.uniform(6) == 1, do: pick.(abbrevs), else: pick.(words))
  first = pick.(opens) <> String.capitalize(hd(body))
  Enum.join([first | tl(body)], pick.([" ", " ", " "])) <> pick.(ends)
end

prose = fn -> Enum.map_join(1..:rand.uniform(5), fn _ -> sentence.() <> pick.(spaces) end) |> String.trim_trailing() end

block = fn ->
  case :rand.uniform(16) do
    1 -> "## " <> sentence.()
    2 -> sentence.() <> "\n" <> pick.(["===", "---", "- -"])
    3 -> "```\n" <> prose.() <> "\n\n" <> prose.() <> "\n```"
    4 -> "| a | b |\n|---|:--:|\n| " <> sentence.() <> " | x |"
    5 -> "a | b\n--- | ---\n1 | 2"
    6 -> "    " <> prose.()
    7 -> pick.(["- ", "* ", "1. ", "2) "]) <> prose.()
    8 -> "<div>" <> sentence.() <> "</div>"
    9 -> pick.(["![a cat. Sat.](x.png)", "[Link. Here](http://x)", "[a](b) more"])
    10 -> pick.(["---", "***", "___ ", "--"])
    11 -> Enum.map_join(String.split(prose.(), "\n"), "\n", &("> " <> &1)) <> "\n>\n> " <> sentence.()
    12 -> "\t" <> sentence.()
    _ -> prose.()
  end
end

doc = fn -> Enum.map_join(1..:rand.uniform(6), pick.(["\n\n", "\n\n\n", "\n \n"]), fn _ -> block.() end) end

n = String.to_integer(System.get_env("N", "3000"))
for _ <- 1..n do
  d = doc.()
  checks = [
    {"blocks", Old.Reading.split(d), Enum.to_list(Temper.MarginaliaCore.blocks(d))},
    {"reflow", Old.Sentences.reflow(d), Temper.MarginaliaCore.reflow(d)},
    {"idempotent", Old.Sentences.reflow(Old.Sentences.reflow(d)), Temper.MarginaliaCore.reflow(Temper.MarginaliaCore.reflow(d))}
  ]
  for b <- Old.Reading.split(d) do
    {o, t} = {Old.Sentences.reflow_block(b), Temper.MarginaliaCore.reflowBlock(b)}
    if o != t, do: (IO.puts("MISMATCH reflow_block\n block=#{inspect(b)}\n old=#{inspect(o)}\n new=#{inspect(t)}"); System.halt(1))
  end
  for {label, o, t} <- checks, o != t do
    IO.puts("MISMATCH #{label}\n doc=#{inspect(d)}\n old=#{inspect(o)}\n new=#{inspect(t)}")
    System.halt(1)
  end
end
IO.puts("#{n} documents: blocks, reflow, reflow_block and reflow twice all identical")
