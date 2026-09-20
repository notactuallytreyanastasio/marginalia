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

  # Set from the prose it has to cover, measured, not from a feel for how long
  # a rewrite should be.
  #
  # The draft that forced this: 12 sections of 1,560-2,290 words, built from
  # 81 paragraphs with a median of 248, a 90th percentile of 382 and a longest
  # of 539. Dense paragraphs. The intuition that "a few paragraphs" is a few
  # hundred words is wrong here by roughly four times — four large ones is
  # 1,528, which a 1,400 ceiling refused while the writer was reasonably
  # calling it a few paragraphs.
  #
  # 2,500 covers a whole section of that draft with room over the largest, so
  # "select the part you want reworked" can mean the part rather than as much
  # of it as fits.
  #
  # The ceiling that actually binds is the provider's, and it was probed
  # rather than assumed: deepseek-flash accepts max_tokens up to at least
  # 65,536 (27,000, 41,500 and 65,536 all return 200). A 2,500-word span asks
  # for 17,500 answer tokens, and LLM adds 24,000 of reasoning headroom on
  # top, so the largest request this can produce is 41,500 — inside what was
  # measured to work.
  @max_span_words 2_500

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
           %{
             reading: out["reading"],
             original: found,
             section: section,
             candidates: candidates,
             # nil context means no single block holds the span, which is also
             # exactly the condition under which a candidate cannot be dropped
             # into a paragraph
             spans_blocks: is_nil(paragraph_around(section.body, found)),
             covers: covered_refs(section, found)
           }}
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

  @doc """
  Every paragraph the span touches, by the ref the page gives it.

  The page dimmed only the paragraph the panel was anchored to, so a rewrite
  of three paragraphs greyed out one of them and left the other two looking
  untouched. Overlap is decided on offsets in the section body rather than by
  asking whether a paragraph is inside the span: a selection that starts
  mid-paragraph covers that paragraph without containing it.

  The ref is built the same way `Marginalia.Reading` builds it — section
  ordinal and zero-based paragraph index — because the page has to be able to
  match them up.
  """
  def covered_refs(section, span) do
    body = section.body

    case :binary.match(body, span) do
      :nomatch ->
        []

      {span_start, span_len} ->
        span_end = span_start + span_len

        body
        |> Marginalia.Reading.split()
        |> Enum.with_index()
        |> Enum.reduce([], fn {para, i}, acc ->
          case :binary.match(body, para) do
            :nomatch ->
              acc

            {p_start, p_len} ->
              p_end = p_start + p_len

              # touching at a boundary is not overlapping
              if p_start < span_end and span_start < p_end,
                do: acc ++ ["s#{section.ordinal}p#{i}"],
                else: acc
          end
        end)
    end
  end

  @doc """
  The answer budget for a span: three candidates plus their two labels each.

  `LLM.call_tool/1` adds reasoning headroom on top of this, so what is asked
  for here is answer only.

  Public because it is the guard against a silent failure. A flat 3,000 was
  ample at 250 words and wrong at 750: the reply comes back
  `finish_reason: "length"`, which the pipeline treats as `{:error, :truncated}`
  — so the symptom is not three short candidates, it is no candidates at all
  and a writer wondering why the button did nothing. Seven tokens per word of
  span is three candidates at ~1.4 tokens a word with room for the JSON.
  """
  def answer_budget(span), do: max(3_000, word_count(span) * 7)

  @doc """
  What the panel calls the span it is about to replace.

  It said "Rewrites of one line" whatever was selected. That was true enough
  when the ceiling was 250 words and false at 2,500 — and the panel renders
  under the FIRST block of a multi-paragraph selection, so the rest of the
  span runs off below it and a writer had nothing on screen saying how much
  was about to be replaced.
  """
  def span_label(span) do
    case word_count_of(span) do
      0 -> "Rewrites"
      n when n < 25 -> "Rewrites of one line"
      n -> "Rewrites of #{n} words"
    end
  end

  @doc """
  The head and tail of the selection, for showing its extent. nil when short
  enough that the writer can already see all of it.
  """
  def span_extent(span) when is_binary(span) do
    flat = span |> String.replace(~r/\s+/, " ") |> String.trim()

    cond do
      flat == "" -> nil
      String.length(flat) <= 120 -> nil
      true -> String.slice(flat, 0, 64) <> " … " <> String.slice(flat, -48, 48)
    end
  end

  def span_extent(_), do: nil

  defp word_count_of(nil), do: 0
  defp word_count_of(text) when is_binary(text), do: word_count(text)
  defp word_count_of(_), do: 0

  @doc """
  Put a candidate back into the paragraph it came from, or refuse.

  `:not_here` rather than a guess. The LiveView used to fall through to the
  candidate when the block did not contain the span, which replaced the WHOLE
  paragraph with a rewrite of text that was not in it: three paragraphs
  selected, the panel anchored to a fourth, one click and the fourth was
  gone. A rewrite that cannot be placed is a refusal, not a substitution.
  """
  def place(block, original, seed)
      when is_binary(block) and is_binary(original) and is_binary(seed) do
    if String.contains?(block, original),
      do: {:ok, String.replace(block, original, seed, global: false)},
      else: :not_here
  end

  def place(_block, _original, seed) when is_binary(seed), do: {:ok, seed}

  @doc "The longest steer taken from the writer. Past this it is a brief, not a note."
  def max_steer_chars, do: 400

  @doc """
  The writer's own instruction, as it goes into the prompt.

  It outranks the standing "differ in kind" rule, because three candidates
  that ignore what was asked for are three wasted candidates — but they still
  have to differ, or the panel is one suggestion printed three times.

  Public because it is pure and because it is the one place writer-supplied
  text enters the prompt: it is bounded here and nowhere else.
  """
  def steer_block(nil), do: ""
  def steer_block(""), do: ""

  def steer_block(steer) when is_binary(steer) do
    case String.trim(steer) do
      "" -> ""
      trimmed -> asked_for(String.slice(trimmed, 0, max_steer_chars()))
    end
  end

  def steer_block(_), do: ""

  defp asked_for(steer) do
    """

    WHAT THE WRITER ASKED FOR, in their words:
    #{steer}

    Every candidate must do this. They still differ from each other, but now
    in HOW they do it, not in whether they do it.
    """
  end

  defp context_block(body, span) do
    case paragraph_around(body, span) do
      nil ->
        ""

      para ->
        "The paragraph it sits in, for context — do not rewrite this, only the span above:\n" <>
          para
    end
  end

  defp ask(work, section, span, opts) do
    scale =
      case word_count(span) do
        n when n > 400 ->
          "\nThis span is #{n} words — a section, not a sentence. Do not reword it line by " <>
            "line: at this length three lightly-reworded versions are indistinguishable and " <>
            "useless. Each candidate should make ONE structural decision and follow it all " <>
            "the way through — cut it to its argument, reorder so the finding leads, or " <>
            "split the pile of claims into a sequence. Say which in `move`."

        n when n > 60 ->
          "\nThis span is #{n} words — several sentences. Your candidates should differ " <>
            "STRUCTURALLY: cut one of the sentences, reorder so the strongest lands first, " <>
            "merge two into one. Rewording every sentence a little is one candidate, not three."

        _ ->
          ""
      end

    user = """
    Manuscript: #{work.title}
    #{if work.intent && work.intent != "", do: "What it is meant to do to a reader: #{work.intent}\n", else: ""}#{steer_block(opts[:steer])}
    THE SELECTED SPAN, to be replaced:#{scale}

    #{span}

    #{context_block(section.body, span)}
    """

    LLM.call_tool(
      tool: @tool,
      provider: opts[:provider],
      model: LLM.default_model(opts[:provider]),
      # the one call whose whole job is the words, so it gets to think
      effort: :high,
      temperature: 0.7,
      max_tokens: answer_budget(span),
      messages: [
        %{"role" => "system", "content" => @prompt},
        %{"role" => "user", "content" => user}
      ]
    )
  end

  # Enough around the span to keep the voice, not so much that the model
  # starts rewriting the section.
  #
  # nil when no single block contains the span, which is the ordinary case
  # once spans can be section-sized: a selection crossing three paragraphs
  # sits in none of them. This used to fall back to the section's first 1,200
  # characters and label them "the paragraph it sits in" — text that is not
  # around the span at all, and at worst is the span itself handed back as
  # its own context. A long span carries its own voice; the honest answer is
  # to send none.
  defp paragraph_around(body, span) do
    body
    |> Marginalia.Reading.split()
    |> Enum.find(fn para -> Marginalia.Selection.in_block(para, span) != nil end)
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
