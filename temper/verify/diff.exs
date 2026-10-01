# Old (the Elixir marginalia shipped) against new (the Temper port), on
# random edits of real prose. Any difference is printed and fails the run.
Code.require_file(Path.join(__DIR__, "old_diff.exs"))
:rand.seed(:exsss, {String.to_integer(System.get_env("SEED", "1")), 2, 3})

corpus =
  Path.wildcard(Path.join(__DIR__, "../../lib/**/*.ex"))
  |> Enum.flat_map(fn f -> Regex.scan(~r/@moduledoc """\n(.*?)"""/s, File.read!(f), capture: :all_but_first) end)
  |> List.flatten()

words = corpus |> Enum.join(" ") |> String.split(~r/\s+/, trim: true)
pick = fn list -> Enum.at(list, :rand.uniform(length(list)) - 1) end
# a lone \r and \r\n too: paragraphs takes \r\n as one newline and \r as text
spaces = [" ", " ", " ", "  ", "\t", "\n", "  ", " ", " ", "\r", "\r\n"]

edit_words = fn ws ->
  Enum.flat_map(ws, fn w ->
    case :rand.uniform(20) do
      1 -> []
      2 -> [w, pick.(words)]
      3 -> [pick.(words)]
      _ -> [w]
    end
  end)
end

join = fn ws -> Enum.map_join(ws, fn w -> w <> pick.(spaces) end) end
para_text = fn paras, sep -> Enum.join(paras, sep) end

new_rows = fn a, b ->
  Temper.MarginaliaCore.rows(a, b)
  |> Enum.map(fn
    %{kind: "same", left: l, right: r} -> {:same, l, r}
    %{kind: "change", left: l, right: r} -> {:change, l, r}
    %{kind: "del", left: l} -> {:del, l}
    %{kind: "ins", right: r} -> {:ins, r}
  end)
end

new_words = fn a, b ->
  Temper.MarginaliaCore.diff(a, b) |> Enum.map(fn %{kind: k, text: t} -> {String.to_atom(k), t} end)
end

check = fn label, old, new, a, b ->
  if old != new do
    IO.puts("MISMATCH #{label}\n a=#{inspect(a)}\n b=#{inspect(b)}\n old=#{inspect(old)}\n new=#{inspect(new)}")
    System.halt(1)
  end
end

n = String.to_integer(System.get_env("N", "2000"))

for k <- 1..n do
  # word diff: a span and an edit of it
  len = :rand.uniform(if rem(k, 50) == 0, do: 400, else: 40)
  base = for _ <- 1..len, do: pick.(words)
  a = join.(base)
  b = if rem(k, 97) == 0, do: join.(for _ <- 1..len, do: pick.(words)), else: join.(edit_words.(base))
  check.("words", Old.Rewrite.diff(a, b), new_words.(a, b), a, b)

  # paragraph diff: paragraphs inserted, deleted, edited, rewrapped
  paras = for _ <- 1..:rand.uniform(8), do: join.(for _ <- 1..:rand.uniform(12), do: pick.(words))
  paras2 =
    Enum.flat_map(paras, fn p ->
      case :rand.uniform(8) do
        1 -> []
        2 -> [p, join.(for _ <- 1..5, do: pick.(words))]
        3 -> [join.(edit_words.(String.split(p)))]
        4 -> [String.replace(p, " ", "\n", global: false)]
        _ -> [p]
      end
    end)
  sep = pick.(["\n\n", "\n\n\n", "\r\n\r\n", "\n \n\n"])
  pa = para_text.(paras, sep)
  pb = para_text.(paras2, pick.(["\n\n", "\r\n\r\n\r\n"]))
  check.("rows", Old.Diff.rows(pa, pb), new_rows.(pa, pb), pa, pb)
end

IO.puts("#{n} word diffs and #{n} paragraph diffs: old and new identical")
