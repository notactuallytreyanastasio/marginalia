# Old Works.Reflow (wrapped?, reflow, align) against the Temper port, on
# random page text built to hit every rule. Any difference fails the run.
Code.require_file(Path.join(__DIR__, "old_reflow.exs"))
:rand.seed(:exsss, {String.to_integer(System.get_env("SEED", "1")), 9, 4})
pick = fn l -> Enum.at(l, :rand.uniform(length(l)) - 1) end

words = ~w(the court held that capacities for-cause well-known re-examination statute
  agency’s decision was arbitrary and capricious under section élan ΟΔΟΣ naïve co-op
  éclair 1983 U.S.C. petitioner respondent’s claim) ++ ["don't", "state-law"]

page_line = fn width ->
  Enum.reduce_while(Stream.repeatedly(fn -> pick.(words) end), "", fn w, acc ->
    next = if acc == "", do: w, else: acc <> " " <> w
    if String.length(next) > width, do: {:halt, acc}, else: {:cont, next}
  end)
end

furniture = [
  "Cite as: 601 U. S. ____ (2024)", "Opinion of the Court", "Syllabus", "Per Curiam",
  "GORSUCH, J., dissenting", "ROBERTS, C. J., concurring in part", "12", "7",
  "2 LANDOR v. LOUISIANA DEPT. OF CORRECTIONS AND", "PUBLIC SAFETY 3", "I", "IV", "B", "## Part One"
]

# a split at the line's end, often followed by its real continuation on the
# next line: capaci-/ties should mend to one word, state-/law keep its
# hyphen when "state-law" appears intact elsewhere
hyphenate = fn line ->
  case :rand.uniform(6) do
    1 -> line <> " capaci-\nties " <> pick.(words)
    2 -> line <> " for-\ncause " <> pick.(words)
    3 -> line <> " state-\nlaw " <> pick.(words)
    4 -> line <> " state-"
    _ -> line
  end
end

page = fn ->
  width = 50 + :rand.uniform(30)
  n = :rand.uniform(60)
  lines =
    for _ <- 1..n do
      case :rand.uniform(12) do
        1 -> pick.(furniture)
        2 -> page_line.(div(width, 3))
        3 -> ""
        _ -> hyphenate.(page_line.(width))
      end
    end
  Enum.join(lines, pick.(["\n", "\n", "\r\n"]))
end

n = String.to_integer(System.get_env("N", "2000"))
:counters.new(3, []) |> then(&Process.put(:stats, &1))
for _ <- 1..n do
  t = page.()
  st = Process.get(:stats)
  if Old.Reflow.wrapped?(t), do: :counters.add(st, 1, 1)
  r0 = Old.Reflow.reflow(t)
  wrapped = Old.Reflow.wrapped?(t)
  if wrapped and String.contains?(t, "capaci-\nties"), do: :counters.add(st, 2, 1)
  if wrapped and (String.contains?(t, "state-\nlaw") or String.contains?(t, "for-\ncause")), do: :counters.add(st, 3, 1)
  _ = r0
  checks = [
    {"wrapped?", Old.Reflow.wrapped?(t), Temper.MarginaliaCore.isWrapped(t)},
    {"reflow", Old.Reflow.reflow(t), Temper.MarginaliaCore.reflowPage(t)}
  ]
  lines = String.split(t, "\n")
  q =
    if length(lines) > 3 do
      s = :rand.uniform(length(lines) - 2)
      Enum.slice(lines, s, 2 + :rand.uniform(2)) |> Enum.join("\n")
    else
      t
    end
  checks = [{"align", Old.Reflow.align(q, t), Temper.MarginaliaCore.align(q, t)} | checks]
  for {label, o, x} <- checks, o != x do
    IO.puts("MISMATCH #{label}\n text=#{inspect(t, limit: :infinity, printable_limit: :infinity)}\n quote=#{inspect(q)}\n old=#{inspect(o)}\n new=#{inspect(x)}")
    System.halt(1)
  end
end
st = Process.get(:stats)
IO.puts("#{n} pages: wrapped?, reflow and align identical (wrapped #{:counters.get(st, 1)}, with a split to mend #{:counters.get(st, 2)}, with a split to keep #{:counters.get(st, 3)})")
