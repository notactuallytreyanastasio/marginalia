defmodule Marginalia.Links.Chat do
  @moduledoc """
  Talking about the relationship between two drafts.

  The draft chat holds one manuscript and answers about what is on its page.
  This one holds a *pair*, and the thing it knows that nothing else does is
  the set of edges between them — which passage develops which, where they
  argue, where they arrived at the same point separately.

  So the question it is good at is not "what does this say" but "how do
  these two sit together": what has already been answered, what has been
  ignored, which of the disagreements is real and which is vocabulary.

  It is handed both maps and every edge, and nothing else. No tools and no
  retrieval — the maps are small, they cache, and a pass that could go
  looking would spend a minute doing it for a question that is answerable
  from the structure it already has.
  """

  import Ecto.Query, warn: false

  alias Marginalia.{LLM, Links, Repo, Works}
  alias Marginalia.Chat.{Conversation, Message}

  @system """
  You are reading two manuscripts that someone has related to each other, and answering
  questions about the relationship.

  You are given both maps — every beat, the spine, the threads, the open questions — and
  every edge drawn between them, with the reason each was drawn. You do NOT have the full
  text of either document. Do not pretend to.

  HOW TO ANSWER
  - Answer about the PAIR. "What does A say about X" is a question for the draft's own chat;
    here the interesting questions are what one document does to the other.
  - Name the specific nodes and edges you are reasoning from. "They disagree about pacing"
    is useless; "A's §5 reading that the safety plan doubles as a moat sits against B's race
    to the top, and neither resolves who writes the rules" is the job.
  - Quote only what you were given. Every beat arrives with the sentence it was anchored to;
    those are real and you may quote them. Anything else, you do not have — say so.
  - An edge you were not given does not exist. If someone asks about a connection that is not
    in the list, say it was not drawn rather than inventing the reasoning for it.
  - Be short. Three tight paragraphs beat a page.

  WHAT YOU DO NOT DO
  - You do not write prose for either manuscript.
  - You do not rank them or say which is better.
  - You do not soften a real disagreement into "both make good points".
  """

  def prompt, do: @system

  def passes do
    [
      %{
        id: "link_chat",
        name: "Talking about a pair",
        model: LLM.default_model(),
        runs: "per message, on a linked pair",
        produces: "answers about how two drafts relate",
        prompt: @system
      }
    ]
  end

  @doc "The conversation for this link, made on first use."
  def conversation(%Links.Link{} = link) do
    case Repo.get_by(Conversation, link_id: link.id) do
      nil ->
        %Conversation{}
        |> Conversation.changeset(%{link_id: link.id, anchor_kind: "link"})
        |> Repo.insert()

      convo ->
        {:ok, convo}
    end
  end

  @doc "Ask about the pair. `history` is the turns so far, oldest first."
  def ask(%Links.Link{} = link, history, opts \\ []) do
    # Ordered for the cache: the system prompt never changes, the two maps
    # change only when a draft is re-read, and the history only grows at the
    # end. A question therefore re-uses everything before it.
    # The cited passages go last, after the history. They change every time
    # someone points at a different line, and anything after them in the
    # list would have its cache thrown away with them.
    messages =
      [
        %{"role" => "system", "content" => @system},
        %{"role" => "system", "content" => card(link)}
      ] ++
        history ++ List.wrap(cited_card(link, opts[:cited]))

    # `LLM.chat` hands back the whole message, not its text. Unwrapping it
    # here is the difference between storing an answer and storing a map:
    # `Message.changeset` casts a map into a string column as invalid, the
    # insert fails, and — if the caller ignores the result — the reply
    # arrives, costs a call, and silently never appears.
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

  @doc """
  The passages behind specific edges, both sides, in full.

  Clicking the line between two paragraphs puts them here. The map already
  names every edge, but it names them — this hands over the actual prose on
  both ends, which is what a question about "this bit" needs.
  """
  def cited_card(_link, nil), do: nil
  def cited_card(_link, []), do: nil

  def cited_card(%Links.Link{} = link, edge_ids) do
    {a, _b} = Links.works(link)

    cited =
      link
      |> Links.edges()
      |> Enum.filter(&(&1.id in edge_ids))

    if cited == [] do
      nil
    else
      body =
        Enum.map_join(cited, "\n\n", fn e ->
          from_side = if e.from.work_id == a.id, do: "A", else: "B"
          to_side = if e.to.work_id == a.id, do: "A", else: "B"

          """
          ## #{String.upcase(String.replace(e.edge_type, "_", " "))}
          Why it was drawn: #{e.rationale}

          ### #{from_side} — #{e.from.title}
          #{Links.passage(e.from)}

          ### #{to_side} — #{e.to.title}
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

  @doc "Both maps and every edge, as one cacheable block."
  def card(%Links.Link{} = link) do
    {a, b} = Links.works(link)
    edges = Links.edges(link)

    """
    # THE PAIR

    A: #{a.title} — #{a.word_count} words
    B: #{b.title} — #{b.word_count} words

    #{if link.summary, do: "How they relate, as already established:\n#{link.summary}\n", else: ""}
    # THE EDGES BETWEEN THEM (#{length(edges)})

    #{Enum.map_join(edges, "\n", &edge_line(&1, a.id))}

    # MAP OF A: #{a.title}
    #{map(a)}

    # MAP OF B: #{b.title}
    #{map(b)}
    """
  end

  defp edge_line(e, a_id) do
    from = if e.from.work_id == a_id, do: "A", else: "B"
    to = if e.to.work_id == a_id, do: "A", else: "B"

    "- #{from}:[#{e.from_id}] #{e.from.title} --#{e.edge_type}--> #{to}:[#{e.to_id}] #{e.to.title}\n    #{e.rationale}"
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
    quote = if n.quote not in [nil, ""], do: "\n    \"#{one_line(n.quote)}\"", else: ""
    "- [#{n.id}]#{where} #{n.title}#{quote}"
  end

  defp one_line(q), do: q |> String.replace(~r/\s+/u, " ") |> String.slice(0, 160)

  @doc "Turns so far, oldest first, in the shape the model wants."
  def history(%Conversation{} = convo, limit \\ 40) do
    Message
    |> where([m], m.conversation_id == ^convo.id)
    |> order_by([m], desc: m.id)
    |> limit(^limit)
    |> select([m], %{role: m.role, content: m.content})
    |> Repo.all()
    |> Enum.reverse()
    |> Enum.map(&%{"role" => &1.role, "content" => &1.content})
  end

  def append(%Conversation{} = convo, role, content) when is_binary(content) do
    %Message{}
    |> Message.changeset(%{conversation_id: convo.id, role: role, content: content})
    |> Repo.insert()
  end
end
