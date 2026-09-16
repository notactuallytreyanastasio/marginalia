defmodule Marginalia.Rewrite do
  @moduledoc """
  Candidate rewrites of one span the writer selected.

  This is the one place in the product that writes prose for the manuscript,
  and the constraints on it are what keep that from swallowing the rest.

  * It only ever runs on a span the writer selected and explicitly asked
    about. There is no path from the chat to here.
  * It returns **candidates**, plural, each labelled with the move it makes
    and what it costs. A single suggestion reads as the answer; three
    labelled ones read as options, which is what they are.
  * It never applies anything. The writer picks, or does neither.
  * The span is verified against the draft first, so a rewrite is always a
    drop-in replacement for something actually on the page.

  The chat stays out of this on purpose. Asking "what is this paragraph
  doing" and asking "give me three versions of this sentence" are different
  requests, and collapsing them is how an editor turns into a ghostwriter.
  """

  require Logger

  alias Marginalia.LLM

  # Generous enough for a few paragraphs dragged over by hand, which is how
  # people actually select. Past this it is not a rewrite, it is a redraft,
  # and three candidates for it would be ghostwriting with extra steps.
  @max_span_words 250

  @prompt """
  The writer has selected one span of their own draft and asked for rewrites of it. This is
  the one thing you do write. Do it well and do it narrowly.

  Return 3 candidates through the tool. Each is a DROP-IN REPLACEMENT for the selected span:
  paste it in place of the original and the paragraph still reads. Not a paragraph, not a
  plan, not advice — the words.

  WHAT MAKES THESE USEFUL
  - They must differ from each other in KIND, not in wording. Three versions of the same move
    is one candidate and two impostors. Cut something / reorder so the object lands first /
    make the implicit claim explicit / drop the hedge / hand the line to a concrete image.
  - Keep the writer's voice. Match their register, their contractions, their sentence music.
    If they write short declaratives, do not hand back a subordinate clause with a semicolon.
  - Keep what the span asserts. You may sharpen a claim, and you may not invent one or
    quietly drop one.
  - Stay close in length unless the move IS the length. A candidate three times longer is a
    different paragraph, not a rewrite.

  FOR EACH ONE
  - "text": the replacement, and nothing else. No quotes around it, no "Option 2:", no
    trailing commentary.
  - "move": what this version does differently, in under ten words. "Cuts the gloss."
    "Puts the number first." "Drops the hedge." This is what the writer reads first.
  - "cost": what it gives up, in under fifteen words. Every rewrite gives something up; a
    candidate with no cost has not been thought about. Say it plainly.

  Also return "reading": one sentence on what the original span is currently doing, so the
  writer can see what you thought you were changing before they read what you changed.
  """

  def prompt, do: @prompt

  @tool %{
    "type" => "function",
    "function" => %{
      "name" => "propose_rewrites",
      "description" => "Offer the writer a few labelled rewrites of the span they selected.",
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "reading" => %{
            "type" => "string",
            "description" => "One sentence on what the original span is doing now."
          },
          "rewrites" => %{
            "type" => "array",
            "description" => "Three candidates, each a different KIND of move.",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "text" => %{
                  "type" => "string",
                  "description" =>
                    "The replacement span itself. No label, no quotes, no commentary."
                },
                "move" => %{
                  "type" => "string",
                  "description" => "What this version does differently. Under ten words."
                },
                "cost" => %{
                  "type" => "string",
                  "description" =>
                    "What it gives up. Under fifteen words. Every rewrite gives something up."
                }
              },
              "required" => ["text", "move", "cost"]
            }
          }
        },
        "required" => ["reading", "rewrites"]
      }
    }
  }

  def tool, do: @tool

  def passes do
    [
      %{
        id: "rewrite",
        name: "On request — rewrite one selected span",
        model: LLM.default_model(),
        runs: "only when the writer selects a span and asks",
        produces: "three labelled candidates, each with the move it makes and what it costs",
        prompt: @prompt
      }
    ]
  end

  @doc """
  Propose rewrites of `span` in `work`.

  `{:ok, %{reading: _, original: _, section: _, candidates: [...]}}`, or
  `{:error, reason}`. The span is verified against the draft first: a
  selection that is not in the manuscript gets no rewrites, because a rewrite
  of something the writer did not write is a rewrite of nothing.
  """
  def propose(work, span, opts \\ []) do
    # length first: it is about what they selected, and it costs nothing,
    # whereas locating a span walks the draft
    with :ok <- check_length(span),
         {:ok, section, found} <- locate(work, span),
         {:ok, %{"rewrites" => raw} = out} <- ask(work, section, found, opts) do
      case clean(raw, found) do
        [] ->
          {:error, :no_candidates}

        candidates ->
          {:ok,
           %{reading: out["reading"], original: found, section: section, candidates: candidates}}
      end
    end
  end

  defp locate(work, span) do
    case Marginalia.Selection.locate(work, span) do
      {:ok, %{section: section, span: found}} -> {:ok, section, found}
      :error -> {:error, :not_in_draft}
    end
  end

  defp check_length(span) do
    case word_count(span) do
      n when n > @max_span_words -> {:error, {:span_too_long, n, @max_span_words}}
      _ -> :ok
    end
  end

  defp word_count(text), do: text |> String.split(~r/\s+/, trim: true) |> length()

  defp ask(work, section, span, opts) do
    scale =
      case word_count(span) do
        n when n > 60 ->
          "\nThis span is #{n} words — several sentences. Your candidates should differ " <>
            "STRUCTURALLY: cut one of the sentences, reorder so the strongest lands first, " <>
            "merge two into one. Rewording every sentence a little is one candidate, not three."

        _ ->
          ""
      end

    user = """
    Manuscript: #{work.title}
    #{if work.intent && work.intent != "", do: "What it is meant to do to a reader: #{work.intent}\n", else: ""}
    THE SELECTED SPAN, to be replaced:#{scale}

    #{span}

    The paragraph it sits in, for context — do not rewrite this, only the span above:
    #{paragraph_around(section.body, span)}
    """

    LLM.call_tool(
      tool: @tool,
      provider: opts[:provider],
      model: LLM.default_model(opts[:provider]),
      # the one call whose whole job is the words, so it gets to think
      effort: :high,
      temperature: 0.7,
      max_tokens: 3_000,
      messages: [
        %{"role" => "system", "content" => @prompt},
        %{"role" => "user", "content" => user}
      ]
    )
  end

  # enough around the span to keep the voice, not so much that the model
  # starts rewriting the section
  defp paragraph_around(body, span) do
    body
    |> Marginalia.Reading.split()
    |> Enum.find(fn para -> Marginalia.Selection.in_block(para, span) != nil end)
    |> case do
      nil -> String.slice(body, 0, 1_200)
      para -> para
    end
  end

  @doc """
  Normalise the model's raw candidates into what the panel renders.

  Public because it is pure and because the walkthrough ships a fixture in
  this shape: when the two drifted, the fixture raised inside `render`, and a
  raise in a LiveView render does not show an error — it drops the socket.
  The tour got to step eight and the page silently stopped answering. The
  test compares a fixture candidate's keys against this function's output, so
  the two cannot part company again.
  """
  def clean(raw, original) do
    normalised = squash(original)

    raw
    |> Enum.filter(&is_map/1)
    |> Enum.map(fn r ->
      %{
        text: trim_text(r["text"]),
        move: one_line(r["move"]),
        cost: one_line(r["cost"])
      }
    end)
    |> Enum.reject(&(&1.text in [nil, ""]))
    # a candidate identical to the original is not a candidate
    |> Enum.reject(&(squash(&1.text) == normalised))
    |> Enum.uniq_by(&squash(&1.text))
    |> Enum.take(4)
  end

  defp squash(nil), do: ""

  defp squash(t),
    do: t |> String.downcase() |> String.replace(~r/[^\p{L}\p{N}]+/u, " ") |> String.trim()

  # models like to wrap the replacement in quotes or prefix it with a label,
  # and either one pasted into the draft is a bug the writer has to fix
  defp trim_text(nil), do: nil

  defp trim_text(t) do
    t
    |> String.trim()
    |> String.replace(~r/^(option|candidate|version)\s*\d*\s*[:.\-—]\s*/i, "")
    |> String.trim()
    |> unwrap_quotes()
    |> String.trim()
  end

  defp unwrap_quotes(t) do
    cond do
      String.starts_with?(t, "\"") and String.ends_with?(t, "\"") -> String.slice(t, 1..-2//1)
      String.starts_with?(t, "“") and String.ends_with?(t, "”") -> String.slice(t, 1..-2//1)
      true -> t
    end
  end

  defp one_line(nil), do: nil
  defp one_line(t), do: t |> String.replace(~r/\s+/, " ") |> String.trim() |> String.slice(0, 160)

  @doc """
  A word-level diff of two spans, as `[{:same | :del | :ins, words}]`.

  Shown beside the candidate so the writer can see what actually changed
  rather than re-reading two similar sentences and hoping.
  """
  def diff(a, b) do
    aw = words(a)
    bw = words(b)
    walk(aw, bw, lcs_table(aw, bw), [])
  end

  defp words(nil), do: []
  defp words(t), do: Regex.scan(~r/\S+\s*/, t) |> Enum.map(&hd/1)

  # A plain longest-common-subsequence table, built bottom-up. The spans are
  # a sentence or two, so this is cheap, and it is deterministic — the same
  # pair always diffs the same way, which matters more here than speed.
  defp lcs_table(a, b) do
    n = length(a)
    m = length(b)
    av = List.to_tuple(a)
    bv = List.to_tuple(b)

    Enum.reduce((n - 1)..0//-1, %{}, fn i, table ->
      Enum.reduce((m - 1)..0//-1, table, fn j, table ->
        value =
          if same?(elem(av, i), elem(bv, j)) do
            1 + Map.get(table, {i + 1, j + 1}, 0)
          else
            max(Map.get(table, {i + 1, j}, 0), Map.get(table, {i, j + 1}, 0))
          end

        Map.put(table, {i, j}, value)
      end)
    end)
  end

  defp same?(x, y), do: String.trim(x) == String.trim(y)

  defp walk(a, b, _table, _acc) when a == [] and b == [], do: []

  defp walk(a, b, table, _acc) do
    av = List.to_tuple(a)
    bv = List.to_tuple(b)
    n = length(a)
    m = length(b)

    step(av, bv, n, m, table, 0, 0, [])
    |> Enum.reverse()
    |> merge()
  end

  defp step(_av, bv, n, m, _table, i, j, acc) when i >= n do
    Enum.reduce(j..(m - 1)//1, acc, fn k, acc -> [{:ins, elem(bv, k)} | acc] end)
  end

  defp step(av, _bv, n, m, _table, i, j, acc) when j >= m do
    Enum.reduce(i..(n - 1)//1, acc, fn k, acc -> [{:del, elem(av, k)} | acc] end)
  end

  defp step(av, bv, n, m, table, i, j, acc) do
    cond do
      same?(elem(av, i), elem(bv, j)) ->
        step(av, bv, n, m, table, i + 1, j + 1, [{:same, elem(bv, j)} | acc])

      Map.get(table, {i, j + 1}, 0) >= Map.get(table, {i + 1, j}, 0) ->
        step(av, bv, n, m, table, i, j + 1, [{:ins, elem(bv, j)} | acc])

      true ->
        step(av, bv, n, m, table, i + 1, j, [{:del, elem(av, i)} | acc])
    end
  end

  defp merge(parts) do
    parts
    |> Enum.chunk_by(&elem(&1, 0))
    |> Enum.map(fn chunk ->
      {elem(hd(chunk), 0), chunk |> Enum.map(&elem(&1, 1)) |> Enum.join()}
    end)
  end
end
