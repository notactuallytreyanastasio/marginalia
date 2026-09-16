defmodule Marginalia.Chat do
  @moduledoc """
  Persisted conversations about one work.

  A writer's thinking about their own draft is the thing worth keeping, so
  conversations survive reloads and the model is sent what was already said —
  its own replies included.
  """

  import Ecto.Query
  alias Marginalia.Repo
  alias Marginalia.Chat.{Conversation, Message}

  # What is rehydrated into the page.
  @ui_limit 60
  # What is actually sent to the model. Resent every turn, so this is a direct
  # multiplier on cost per message — keep it well under the UI limit.
  @context_limit 20

  def context_limit, do: @context_limit

  def latest_conversation(work_id) do
    Conversation
    |> where([c], c.work_id == ^work_id and c.anchor_kind == "work")
    |> order_by([c], desc: c.id)
    |> limit(1)
    |> Repo.one()
  end

  def get_or_create_conversation(work_id) do
    case latest_conversation(work_id) do
      nil -> create_conversation(work_id)
      convo -> {:ok, convo}
    end
  end

  def create_conversation(work_id, mode \\ nil) do
    %Conversation{}
    |> Conversation.changeset(%{
      work_id: work_id,
      mode: mode || Marginalia.Chat.Editor.default_mode()
    })
    |> Repo.insert()
  end

  @doc "Switch the stance of an existing conversation. It keeps its history."
  def set_mode(%Conversation{} = c, mode) do
    c |> Conversation.changeset(%{mode: mode}) |> Repo.update()
  end

  def list_conversations(work_id) do
    Conversation
    |> where([c], c.work_id == ^work_id and c.anchor_kind == "work")
    |> order_by([c], desc: c.id)
    |> limit(30)
    |> Repo.all()
  end

  def get_conversation(work_id, id) do
    Repo.get_by(Conversation, id: id, work_id: work_id)
  end

  @doc """
  Conversations with enough about each to pick one from a list.

  A thread with no name is named after the question that started it — that is
  what the writer remembers it by, and asking them to title a chat before
  they have had it is a form to fill in before a thought.
  """
  def conversation_summaries(work_id) do
    convos = list_conversations(work_id)
    ids = Enum.map(convos, & &1.id)

    counts =
      Message
      |> where([m], m.conversation_id in ^ids)
      |> group_by([m], m.conversation_id)
      |> select([m], {m.conversation_id, count(m.id)})
      |> Repo.all()
      |> Map.new()

    firsts =
      Message
      |> where([m], m.conversation_id in ^ids and m.role == "user")
      |> order_by([m], asc: m.id)
      |> select([m], {m.conversation_id, m.content})
      |> Repo.all()
      |> Enum.reverse()
      |> Map.new()

    Enum.map(convos, fn c ->
      %{
        id: c.id,
        mode: c.mode,
        messages: Map.get(counts, c.id, 0),
        title: c.title || summarise(Map.get(firsts, c.id)),
        at: c.inserted_at
      }
    end)
  end

  defp summarise(nil), do: "New thread"

  defp summarise(text) do
    text = text |> String.replace(~r/\s+/, " ") |> String.trim()
    if String.length(text) > 52, do: String.slice(text, 0, 51) <> "…", else: text
  end

  def history(conversation_id, limit \\ @ui_limit) do
    Message
    |> where([m], m.conversation_id == ^conversation_id)
    |> order_by([m], desc: m.id)
    |> limit(^limit)
    |> select([m], %{role: m.role, content: m.content})
    |> Repo.all()
    |> Enum.reverse()
    |> Enum.map(&%{"role" => &1.role, "content" => &1.content})
  end

  def context_window(history), do: Enum.take(history, -@context_limit)

  @doc "Append a turn. Never raises — a chat that 500s on a write is worse than one that forgets."
  def append(conversation_id, role, content) when role in ["user", "assistant"] do
    %Message{}
    |> Message.changeset(%{conversation_id: conversation_id, role: role, content: content})
    |> Repo.insert()

    :ok
  rescue
    _ -> :ok
  end

  def append(_c, _r, _co), do: :ok

  def delete_conversation(%Conversation{} = c), do: Repo.delete(c)

  @doc """
  Word-scored search across every conversation about this work.

  Backs the `recall_sessions` tool: the reader can find what it already said
  to this writer, including notes they overruled. Only the exchange text is
  searched — that is what the model needs in order not to repeat itself.
  """
  def search(work_id, query, limit \\ 8) do
    terms =
      (query || "")
      |> String.downcase()
      |> String.split(~r/[^a-z0-9']+/, trim: true)
      |> Enum.reject(&(String.length(&1) < 3))

    if terms == [] do
      []
    else
      Message
      |> join(:inner, [m], c in Conversation, on: c.id == m.conversation_id)
      |> where([_m, c], c.work_id == ^work_id)
      |> order_by([m], desc: m.id)
      |> limit(400)
      |> select([m], %{role: m.role, content: m.content, at: m.inserted_at})
      |> Repo.all()
      |> Enum.map(fn m ->
        text = String.downcase(m.content || "")
        {m, Enum.count(terms, &String.contains?(text, &1))}
      end)
      |> Enum.filter(fn {_m, n} -> n > 0 end)
      |> Enum.sort_by(fn {_m, n} -> -n end)
      |> Enum.take(limit)
      |> Enum.map(fn {m, _n} ->
        %{who: m.role, said: String.slice(m.content, 0, 600), at: m.at}
      end)
    end
  end


  # ==========================================================================
  # The quota
  # ==========================================================================

  # Uploading needs no account, so anyone can spend the deploy's model credit.
  # A cap per account is the cheap version of a paywall: enough messages to
  # find out whether the thing is any good, not enough to run a book club on
  # someone else's bill.
  @message_limit 100

  @doc "How many questions one account may ask, ever."
  def message_limit, do: @message_limit

  @doc """
  Questions this account has asked, across every draft it owns.

  Counted from the stored messages rather than a counter column, so it cannot
  drift out of step with what actually happened and a deleted draft gives the
  quota back.
  """
  def messages_sent(user_id) do
    Message
    |> join(:inner, [m], c in Conversation, on: c.id == m.conversation_id)
    |> join(:inner, [_m, c], w in Marginalia.Works.Work, on: w.id == c.work_id)
    |> where([m, _c, w], w.user_id == ^user_id and m.role == "user")
    |> Repo.aggregate(:count)
  end

  @doc "Questions left, or `:unlimited` for the owner of the deploy."
  def remaining(user) do
    if Marginalia.Accounts.owner?(user) do
      :unlimited
    else
      max(@message_limit - messages_sent(user.id), 0)
    end
  end

  @doc "Whether this account may ask another question."
  def allowed?(user), do: remaining(user) != 0


  # ==========================================================================
  # Threads pinned to a place in the draft
  # ==========================================================================

  @doc """
  The thread for one paragraph, creating it the first time.

  One thread per place. Clicking the same paragraph twice returns to the
  conversation already there rather than starting a second one beside it —
  a margin that forgets what was said in it last week is just a text box.
  """
  def thread_for_block(work_id, section_id, block_ref, opts \\ []) do
    case Repo.get_by(Conversation, work_id: work_id, block_ref: block_ref) do
      nil ->
        %Conversation{}
        |> Conversation.changeset(%{
          work_id: work_id,
          section_id: section_id,
          block_ref: block_ref,
          anchor_kind: if(opts[:quote], do: "span", else: "block"),
          quote: opts[:quote],
          mode: opts[:mode] || Marginalia.Chat.Editor.default_mode()
        })
        |> Repo.insert()

      convo ->
        # a selection inside a paragraph that already has a thread joins it,
        # and narrows what the thread is about
        if opts[:quote] && opts[:quote] != convo.quote do
          convo
          |> Conversation.changeset(%{quote: opts[:quote], anchor_kind: "span"})
          |> Repo.update()
        else
          {:ok, convo}
        end
    end
  end

  @doc "Every pinned thread on this draft, keyed by the block it is pinned to."
  def threads_by_block(work_id) do
    Conversation
    |> where([c], c.work_id == ^work_id and not is_nil(c.block_ref))
    |> Repo.all()
    |> Map.new(fn c -> {c.block_ref, thread_summary(c)} end)
  end

  defp thread_summary(c) do
    count = Repo.aggregate(where(Message, [m], m.conversation_id == ^c.id), :count)
    %{id: c.id, messages: count, quote: c.quote, resolved: c.resolved_at != nil, mode: c.mode}
  end

  @doc "Mark a pinned thread settled, or reopen it."
  def resolve_thread(%Conversation{} = c, resolved?) do
    at = if resolved?, do: DateTime.utc_now() |> DateTime.truncate(:second)
    c |> Conversation.changeset(%{resolved_at: at}) |> Repo.update()
  end

  @doc "Whole-draft conversations only — the ones the drawer's strip lists."
  def list_open_conversations(work_id) do
    Conversation
    |> where([c], c.work_id == ^work_id and c.anchor_kind == "work")
    |> order_by([c], desc: c.id)
    |> limit(30)
    |> Repo.all()
  end

end
