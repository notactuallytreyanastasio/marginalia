defmodule D do
  def ranges(pred) do
    cps = for cp <- 128..0x10FFFF, not (cp in 0xD800..0xDFFF), pred.(cp), do: cp
    Enum.reduce(cps, [], fn
      cp, [{lo, hi} | rest] when cp == hi + 1 -> [{lo, cp} | rest]
      cp, acc -> [{cp, cp} | acc]
    end) |> Enum.reverse()
  end
  def m(re), do: fn cp -> Regex.match?(re, <<cp::utf8>>) end
end
out = [
  {"space", D.ranges(D.m(~r/\A\s\z/u))},
  {"upper", D.ranges(D.m(~r/\A\p{Lu}\z/u))},
  {"digit", D.ranges(D.m(~r/\A\d\z/u))},
  {"letter", D.ranges(D.m(~r/\A\p{L}\z/u))},
  {"number", D.ranges(D.m(~r/\A\p{N}\z/u))},
  {"upchanged", D.ranges(fn cp -> String.upcase(<<cp::utf8>>) != <<cp::utf8>> end)}
]
for {n, r} <- out, do: IO.puts("#{n} #{length(r)} " <> Enum.map_join(r, ",", fn {a, b} -> "#{a}-#{b}" end))
