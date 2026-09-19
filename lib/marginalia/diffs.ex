defmodule Marginalia.Diffs do
  @moduledoc """
  Reading a unified diff well enough to quote code out of it.

  A guide's code samples have to be real. A model asked for "the important
  part of this change" will produce plausible code that appears nowhere in
  the repository, and a teaching document whose samples do not compile is
  worse than one with no samples. So the model quotes a line and this module
  finds it in the actual patch and hands back the hunk around it.

  What comes back drops the removed lines and strips the `+`. Someone
  learning the method wants the code that ended up there, not the edit that
  produced it — the edit is a fact about this project's history, which is
  exactly what a method is not.
  """

  defmodule Hunk do
    @moduledoc false
    defstruct [:path, :heading, lines: []]
  end

  @file_re ~r/^diff --git a\/(?<a>.+?) b\/(?<b>.+)$/
  @hunk_re ~r/^@@ -\d+(?:,\d+)? \+\d+(?:,\d+)? @@(?<heading>.*)$/

  @doc "Every hunk in a patch, in order."
  def parse(patch) when is_binary(patch) do
    patch
    |> String.split("\n")
    |> Enum.reduce({[], nil, ""}, fn line, {hunks, current, path} ->
      cond do
        caps = Regex.named_captures(@file_re, line) ->
          {push(hunks, current), nil, caps["b"]}

        caps = Regex.named_captures(@hunk_re, line) ->
          {push(hunks, current), %Hunk{path: path, heading: String.trim(caps["heading"])}, path}

        current && String.first(line) in [" ", "+", "-"] ->
          {hunks, %{current | lines: [line | current.lines]}, path}

        true ->
          {hunks, current, path}
      end
    end)
    |> then(fn {hunks, current, _} -> push(hunks, current) end)
    |> Enum.reverse()
    |> Enum.map(fn h -> %{h | lines: Enum.reverse(h.lines)} end)
  end

  def parse(_), do: []

  defp push(hunks, nil), do: hunks
  defp push(hunks, hunk), do: [hunk | hunks]

  @doc "The paths a patch touches, in order of first appearance."
  def files(patch) do
    patch |> parse() |> Enum.map(& &1.path) |> Enum.uniq()
  end

  @doc "Only what this hunk added, for matching a quote against."
  def added(%Hunk{lines: lines}) do
    lines
    |> Enum.filter(&String.starts_with?(&1, "+"))
    |> Enum.map_join("\n", &String.slice(&1, 1..-1//1))
  end

  @doc """
  The hunk as you would paste it into a document.

  Additions with their marker stripped, context kept so the excerpt stands on
  its own, removals dropped.
  """
  def sample(%Hunk{lines: lines}) do
    lines
    |> Enum.filter(&String.starts_with?(&1, ["+", " "]))
    |> Enum.map_join("\n", &String.slice(&1, 1..-1//1))
    |> String.trim("\n")
  end

  @doc """
  The hunk whose added lines contain `quote`, or nil.

  Matching goes through `Cuts.locate/2`, so re-indentation is forgiven and
  invention is not — the same rule every other quote in the app is held to.
  """
  def find(patch, quote) when is_binary(quote) do
    patch
    |> parse()
    |> Enum.find(fn h -> Marginalia.Cuts.locate(quote, added(h)) end)
  end

  def find(_patch, _quote), do: nil
end
