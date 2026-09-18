defmodule Marginalia.Cuts do
  @moduledoc """
  Reading several drafts along one line.

  A draft's own read is already here: `Marginalia.Analysis` turns one
  manuscript into a map. This is the other axis. A reader picks paragraphs out
  of four opinions and asks what they amount to together — a question no one
  of them answers, and which the margin of any single draft has nowhere to put.

  Two rules shape the whole module.

  The model is shown the picked passages and nothing else. Not the rest of the
  section, not the work's map, not the other drafts in the folder. Handed the
  surrounding context it answers an easier question and returns something the
  reader could have got from the table of contents.

  Every claim has to quote a picked passage, and a claim resting on one
  passage is not a finding about several drafts — it is a restatement of one.
  So two verifiable citations are the floor, and anything that cannot be
  located in the text it names is dropped and counted rather than softened.
  """

  import Ecto.Query

  alias Marginalia.{LLM, Reading, Repo, Works}
  alias Marginalia.Cuts.{Cut, Pick}
  alias Marginalia.Works.Work

  @max_picks 40

  # ==========================================================================
  # Addressing a passage
  # ==========================================================================

  @doc """
  Every block of a work, addressable and stable.

  A ref is `s<section ordinal>b<index>`, which is the same shape the reading
  view already uses for anchors. Blocks come from `Reading.split/1` — the
  splitter the rest of the app reads with — so a passage picked here is the
  same passage the margin notes hang off, rather than a second opinion about
  where paragraphs begin.
  """
  def blocks(%Work{} = work) do
    work.id
    |> Works.list_sections()
    |> Enum.flat_map(fn section ->
      section.body
      |> Reading.split()
      |> Enum.with_index(1)
      |> Enum.map(fn {text, i} ->
        %{
          ref: "s#{section.ordinal}b#{i}",
          section_ordinal: section.ordinal,
          section_title: section.title,
          text: text,
          words: length(String.split(text, ~r/\s+/, trim: true))
        }
      end)
    end)
  end

  def block(%Work{} = work, ref) do
    work |> blocks() |> Enum.find(&(&1.ref == ref))
  end

  @doc """
  Find `needle` in `haystack` and return *the haystack's own wording*.

  Quoting has to tolerate re-wrapping and nothing else. Prose here is stored
  with the line breaks it was written with, and a model asked to cite a
  passage reflows it — so a byte-exact test rejects almost every true citation
  for a reason that means nothing about whether the model read the text.

  Collapsing whitespace on both sides costs no strictness that matters: every
  token must still be present, in order, in that passage. What comes back is
  located through an index back into the original, so what gets stored is the
  draft's own characters rather than the model's version of them.
  """
  def locate(needle, haystack)
      when is_binary(needle) and is_binary(haystack) do
    cond do
      String.trim(needle) == "" -> nil
      String.contains?(haystack, needle) -> needle
      true -> locate_loose(needle, haystack)
    end
  end

  def locate(_, _), do: nil

  defp locate_loose(needle, haystack) do
    flat_needle = needle |> String.replace(~r/\s+/, " ") |> String.trim()
    {flat_hay, back} = flatten(haystack)

    case flat_needle != "" and :binary.match(flat_hay, flat_needle) do
      {at, len} ->
        start = Enum.at(back, at)
        stop = Enum.at(back, at + len - 1)
        binary_part(haystack, start, stop - start + 1)

      _ ->
        nil
    end
  end

  # the whitespace-collapsed string, plus each byte's offset in the original
  defp flatten(text) do
    text
    |> :binary.bin_to_list()
    |> Enum.with_index()
    |> Enum.reduce({[], [], false}, fn {byte, i}, {out, back, prev_ws?} ->
      cond do
        byte in [?\s, ?\n, ?\t, ?\r] ->
          if prev_ws? or out == [], do: {out, back, true}, else: {[?\s | out], [i | back], true}

        true ->
          {[byte | out], [i | back], false}
      end
    end)
    |> then(fn {out, back, _} ->
      {out |> Enum.reverse() |> :binary.list_to_bin(), Enum.reverse(back)}
    end)
  end

  # ==========================================================================
  # Cuts
  # ==========================================================================

  def list_cuts(user_id) do
    Cut
    |> where([c], c.user_id == ^user_id)
    |> order_by([c], desc: c.id)
    |> preload(picks: :work)
    |> Repo.all()
  end

  def get_cut(user_id, id) do
    Cut
    |> where([c], c.user_id == ^user_id and c.id == ^id)
    |> preload(picks: :work)
    |> Repo.one()
  end

  def change_cut(cut \\ %Cut{}, attrs \\ %{}), do: Cut.changeset(cut, attrs)

  @doc """
  Make a cut from passages picked across drafts.

  `picks` is a list of `{work_id, block_ref}`. The quote is read here from the
  work rather than taken from the caller: a passage is whatever the draft
  actually says, and a browser that has been open for an hour does not get to
  decide that.
  """
  def create_cut(user_id, attrs, picks) do
    picks = Enum.take(Enum.uniq(picks), @max_picks)

    Repo.transaction(fn ->
      with {:ok, cut} <- %Cut{user_id: user_id} |> Cut.changeset(attrs) |> Repo.insert(),
           {:ok, _} <- put_picks(cut, user_id, picks) do
        get_cut(user_id, cut.id)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp put_picks(%Cut{} = cut, user_id, picks) do
    rows =
      picks
      |> Enum.with_index()
      |> Enum.map(fn {{work_id, ref}, i} ->
        with %Work{} = work <- Works.get_work(user_id, work_id),
             %{text: text} <- block(work, ref) do
          %{cut_id: cut.id, work_id: work.id, block_ref: ref, quote: text, ordinal: i}
        else
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    case rows do
      [] ->
        {:error, :no_passages}

      rows ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        rows = Enum.map(rows, &Map.merge(&1, %{inserted_at: now, updated_at: now}))
        {:ok, Repo.insert_all(Pick, rows)}
    end
  end

  def delete_cut(%Cut{} = cut), do: Repo.delete(cut)

  @doc """
  What the picks currently are, as a fingerprint.

  Stored alongside a result so the page can tell an analysis of *these*
  passages from one made before somebody changed them.
  """
  def content_sha(%Cut{picks: picks}) when is_list(picks) do
    picks
    |> Enum.sort_by(&{&1.work_id, &1.block_ref})
    |> Enum.map_join("\n", & &1.quote)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc "Whether the stored result is about the passages the cut now holds."
  def current?(%Cut{content_sha: nil}), do: false
  def current?(%Cut{} = cut), do: cut.content_sha == content_sha(cut)

  @doc "The drafts a cut passes through, in order."
  def works(%Cut{picks: picks}) when is_list(picks) do
    picks |> Enum.map(& &1.work) |> Enum.uniq_by(& &1.id)
  end

  def set_status(%Cut{} = cut, status, detail \\ nil) do
    cut |> Ecto.Changeset.change(status: status, status_detail: detail) |> Repo.update()
  end

  # ==========================================================================
  # The read
  # ==========================================================================

  @system """
  You are given passages a reader picked out of several different documents, \
  and nothing else. Say what they amount to together.

  You have not been shown the rest of any document. Do not reach for context \
  you do not have, and do not summarise the passages back — the reader has \
  just read them. Say what is true across them that is not visible in any one.

  Every piece of evidence must quote one of the given passages and name the \
  document it came from by its number. A program checks each quote against \
  that document's passages and drops the ones it cannot find, so an \
  approximate quote is a discarded claim.

  An empty list is a real answer. If the passages have nothing in common, say \
  so in the thesis and return no threads.

  Reply with one JSON object and nothing else.
  """

  @doc """
  Read a cut, and store only what could be checked.

  Synchronous and slow by design — the caller is a LiveView that has already
  told the reader it is thinking. Returns the updated cut.
  """
  def read(%Cut{} = cut) do
    sha = content_sha(cut)
    docs = documents(cut)

    case LLM.json(
           model: LLM.default_model(),
           effort: :high,
           temperature: 0.3,
           max_tokens: 8_000,
           messages: [
             %{"role" => "system", "content" => @system},
             %{"role" => "user", "content" => prompt(cut, docs)}
           ]
         ) do
      {:ok, raw} ->
        {result, dropped} = validate(raw, docs)

        cut
        |> Cut.result_changeset(
          Map.merge(result, %{
            dropped: dropped,
            content_sha: sha,
            status: "read"
          })
        )
        |> Repo.update()

      {:error, reason} ->
        set_status(cut, "failed", inspect(reason))
    end
  end

  # Documents numbered for the model, each holding only its picked passages.
  defp documents(%Cut{picks: picks}) do
    picks
    |> Enum.group_by(& &1.work_id)
    |> Enum.sort_by(fn {_id, [p | _]} -> p.ordinal end)
    |> Enum.with_index(1)
    |> Enum.map(fn {{_work_id, group}, n} ->
      %{n: n, work: hd(group).work, picks: Enum.sort_by(group, & &1.ordinal)}
    end)
  end

  defp prompt(%Cut{} = cut, docs) do
    asked =
      if cut.question && String.trim(cut.question) != "",
        do: "The reader asks: #{cut.question}\n\n",
        else: ""

    body =
      Enum.map_join(docs, "\n", fn d ->
        passages =
          Enum.map_join(d.picks, "\n\n", fn p -> "(#{p.block_ref})\n#{p.quote}" end)

        "### Document #{d.n}: #{d.work.title}\n\n#{passages}\n"
      end)

    """
    #{asked}Passages:

    #{body}
    ---

    Report:

    - `thesis`: one or two sentences. What these passages, together, establish.
      If they establish nothing together, say that.
    - `threads`: things true across two or more documents that no single
      passage states. Each: `claim` (one sentence) and `evidence` — two or more
      entries, each `{"document": N, "quote": "..."}` quoted from that document.
    - `tensions`: places these passages disagree, or where one revises another.
      Same shape. `[]` if there are none.
    - `not_supported`: one sentence naming something a reader might expect this
      selection to show but which these passages do not support. `""` if none.

    Shape:

    {"thesis": "...",
     "threads": [{"claim": "...", "evidence": [{"document": 1, "quote": "..."}]}],
     "tensions": [],
     "not_supported": "..."}
    """
  end

  # --- validation -----------------------------------------------------------

  defp validate(raw, docs) do
    by_n = Map.new(docs, fn d -> {d.n, d} end)

    {threads, d1} = check_group(raw["threads"], by_n, "thread")
    {tensions, d2} = check_group(raw["tensions"], by_n, "tension")

    {%{
       thesis: text(raw["thesis"]),
       threads: threads,
       tensions: tensions,
       not_supported: text(raw["not_supported"])
     }, d1 ++ d2}
  end

  defp check_group(items, by_n, label) when is_list(items) do
    Enum.reduce(items, {[], []}, fn item, {kept, dropped} ->
      claim = text(item["claim"])

      if claim == "" do
        {kept, dropped ++ ["#{label}: no claim"]}
      else
        {evidence, bad} = check_evidence(item["evidence"], by_n, label, claim)

        if length(evidence) >= 2 do
          {kept ++ [%{"claim" => claim, "evidence" => evidence}], dropped ++ bad}
        else
          {kept,
           dropped ++
             bad ++
             ["#{label} #{short(claim)}: #{length(evidence)} verifiable citation(s), needs 2"]}
        end
      end
    end)
  end

  defp check_group(_items, _by_n, _label), do: {[], []}

  defp check_evidence(evidence, by_n, label, claim) when is_list(evidence) do
    Enum.reduce(evidence, {[], []}, fn ev, {kept, bad} ->
      n = as_int(ev["document"])
      quote = text(ev["quote"])
      doc = Map.get(by_n, n)

      found =
        doc && quote != "" &&
          Enum.find_value(doc.picks, fn p -> locate(quote, p.quote) end)

      cond do
        is_nil(doc) ->
          {kept,
           bad ++
             ["#{label} #{short(claim)}: document #{inspect(ev["document"])} is not in this cut"]}

        found ->
          {kept ++ [%{"document" => n, "work_id" => doc.work.id, "quote" => found}], bad}

        true ->
          {kept, bad ++ ["#{label} #{short(claim)}: quote is not in document #{n}"]}
      end
    end)
  end

  defp check_evidence(_evidence, _by_n, label, claim),
    do: {[], ["#{label} #{short(claim)}: no evidence"]}

  defp text(v) when is_binary(v), do: String.trim(v)
  defp text(_), do: ""

  defp as_int(v) when is_integer(v), do: v

  defp as_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      _ -> nil
    end
  end

  defp as_int(_), do: nil

  defp short(s), do: inspect(String.slice(s, 0, 40))
end
