defmodule Marginalia.Cases.Chat do
  @moduledoc """
  Talking about a case, rather than about a pair inside it.

  `Marginalia.Links.Chat` holds two documents and the edges between them.
  That is the right shape for the pairwise reading and the wrong one
  here: on the whole-case view the reader is looking at one document with
  every other document in the margin at once, and the question they have
  is almost always about three of them — what the Court said, what the
  dissent said back, and what the advocate had already conceded at the
  lectern. Handed only a pair, the answer cannot reach the third.

  So this holds the document being read, every other document related to
  it, and every edge from the lead out to each of them — including the
  ones that leave the case entirely, because "the same Court said the
  opposite three weeks ago" is the best thing on the page when it is
  there.

  ## Documents are named

  The pairwise chat labels its two documents A and B, which is right for
  a prompt about a pair and reads badly coming back out: answers arrive
  talking about "A:[4030] ↔ B:[7497]". With four or five documents in
  play, A and B would not even be enough. Everything here is named the
  way the page names it — "Dissent (Sotomayor)", "Argument: Amit
  Agarwal" — so the answer comes back in the reader's vocabulary and the
  node ids never leave the building.
  """

  alias Marginalia.{Cases, LLM, Links, Works}

  @system """
  You are reading one document from a court case with every other document in that case
  laid against it, and answering questions about how they sit together.

  You are given the map of each document — every beat, the spine, the threads, the open
  questions — and every connection drawn between the document being read and the others,
  with the reason each was drawn. You do NOT have the full text of anything. Do not
  pretend to.

  HOW TO ANSWER
  - Answer about the RELATIONSHIPS. "What does the opinion say about standing" is a
    question for one document; here the interesting questions are what these documents do
    to each other — what the dissent already answered, what the advocate conceded that the
    opinion then relied on, where two of them collide on the same paragraph.
  - Name documents the way the reader sees them: "the dissent", "Gen. Sauer's argument",
    "the concurrence". Never by letter, and never by node number — those are plumbing.
  - Quote only what you were given. Every beat arrives with the sentence it was anchored
    to; those are real and you may quote them. Anything else, say you do not have.
  - A connection you were not given does not exist. If asked about one that is not in the
    list, say it was not drawn rather than inventing why it would have been.
  - When a connection comes from a different case, say so. Two cases agreeing is a
    different claim from two documents in one case agreeing.
  - Be short. Three tight paragraphs beat a page.

  WHAT YOU DO NOT DO
  - You do not write prose for any of these documents.
  - You do not say which side should have won.
  - You do not soften a real disagreement into "both make good points".
  - You are not giving legal advice, and you do not pretend the reading is authoritative.
  """

  def prompt, do: @system

  def passes do
    [
      %{
        id: "case_chat",
        name: "Talking about a case",
        model: LLM.default_model(),
        runs: "per message, on a case being read",
        produces: "answers about how the documents of a case sit together",
        prompt: @system
      }
    ]
  end

  @doc """
  Ask about the case. `history` is the turns so far, oldest first.

  `reading` is what `Marginalia.Cases.reading/2` returns.
  """
  def ask(reading, history, opts \\ []) do
    # Ordered for the cache: the prompt never changes, the card changes
    # only when something is re-read or re-linked, history grows at the
    # end, and the cited passages go last because they change every time
    # the reader points somewhere new.
    messages =
      [
        %{"role" => "system", "content" => @system},
        %{"role" => "system", "content" => card(reading)}
      ] ++ history ++ List.wrap(cited_card(reading, opts[:cited]))

    case LLM.chat(
           provider: opts[:provider],
           model: LLM.default_model(opts[:provider]),
           effort: :low,
           temperature: 0.5,
           max_tokens: 4_000,
           messages: messages
         ) do
      {:ok, %{"content" => text}} when is_binary(text) and text != "" -> {:ok, text}
      {:ok, _} -> {:error, :empty_reply}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Every edge the reader could point at, across all the sources."
  def edges(reading) do
    Enum.flat_map(reading.sources, fn s ->
      Enum.map(Links.edges(s.link), &{s, &1})
    end)
  end

  @doc """
  The passages behind the connections the reader is pointing at, in full.
  """
  def cited_card(_reading, nil), do: nil
  def cited_card(_reading, []), do: nil

  def cited_card(reading, edge_ids) do
    cited = reading |> edges() |> Enum.filter(fn {_s, e} -> e.id in edge_ids end)

    if cited == [] do
      nil
    else
      body =
        Enum.map_join(cited, "\n\n", fn {s, e} ->
          """
          ## #{String.upcase(String.replace(e.edge_type, "_", " "))}#{from_case(s)}
          Why it was drawn: #{e.rationale}

          ### #{whose(e.from, reading, s)}
          #{Links.passage(e.from)}

          ### #{whose(e.to, reading, s)}
          #{Links.passage(e.to)}
          """
        end)

      %{
        "role" => "system",
        "content" =>
          "The reader is pointing at these connections and wants to talk about them. " <>
            "Both passages are given in full — quote from them freely.\n\n" <> body
      }
    end
  end

  @doc "The case, its documents and every connection from the one being read."
  def card(reading) do
    lead = reading.lead

    """
    # THE DOCUMENT BEING READ

    #{name(lead)} — #{lead.word_count} words

    # READ AGAINST (#{length(reading.sources)})

    #{Enum.map_join(reading.sources, "\n", &against_line/1)}

    # THE CONNECTIONS (#{length(edges(reading))})

    #{Enum.map_join(edges(reading), "\n", fn {s, e} -> edge_line(s, e, reading) end)}

    # MAP OF #{String.upcase(name(lead))}
    #{map(lead)}
    #{Enum.map_join(reading.sources, "\n", fn s -> "\n# MAP OF #{String.upcase(name(s.work))}#{from_case(s)}\n#{map(s.work)}" end)}
    """
  end

  defp against_line(s) do
    "- #{name(s.work)} — #{s.work.word_count} words#{from_case(s)}" <>
      if(s.link.summary, do: "\n    #{Links.summary(s.link)}", else: "")
  end

  defp edge_line(s, e, reading) do
    "- #{whose(e.from, reading, s)} --#{e.edge_type}--> #{whose(e.to, reading, s)}\n    #{e.rationale}"
  end

  # which document a node belongs to, by name rather than by letter
  defp whose(node, reading, s) do
    cond do
      node.work_id == reading.lead.id -> name(reading.lead)
      node.work_id == s.work.id -> name(s.work)
      true -> "another document"
    end <> " — " <> node.title
  end

  defp from_case(%{elsewhere: nil}), do: ""
  defp from_case(%{elsewhere: name}), do: " (from #{name}, a different case)"

  # the page calls it "Dissent (Sotomayor)", so the answer should too
  defp name(work) do
    case String.split(work.title, " — ", parts: 2) do
      [_case, rest] -> rest
      [whole] -> whole
    end
  end

  defp map(work) do
    sections = Works.list_sections(work.id) |> Map.new(&{&1.id, &1.ordinal})

    work.id
    |> Works.list_nodes()
    |> Enum.group_by(& &1.node_type)
    |> Enum.map_join("\n", fn {type, nodes} ->
      "\n## #{type}\n" <> Enum.map_join(nodes, "\n", &node_line(&1, sections))
    end)
  end

  defp node_line(n, sections) do
    where = if n.section_id, do: " (§#{sections[n.section_id]})", else: ""
    quoted = if n.quote not in [nil, ""], do: "\n    \"#{one_line(n.quote)}\"", else: ""
    "- #{n.title}#{where}#{quoted}"
  end

  defp one_line(q), do: q |> String.replace(~r/\s+/u, " ") |> String.slice(0, 160)

  @doc false
  # so the prompts page can list this alongside the others
  def for_case(c, lead_id), do: Cases.reading(c, lead_id)
end
