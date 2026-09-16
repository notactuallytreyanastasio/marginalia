defmodule Marginalia.QuotaTest do
  @moduledoc """
  Uploading needs no account, so the model credit is spendable by anyone who
  finds the site. The cap is what stands between that and a bill.
  """
  use Marginalia.DataCase, async: true

  alias Marginalia.{Chat, Works}
  import Marginalia.AccountsFixtures

  setup do
    user = user_fixture()
    {:ok, work} = Works.create_work(user.id, %{"title" => "W", "body" => String.duplicate("w ", 300)})
    {:ok, convo} = Chat.get_or_create_conversation(work.id)
    %{user: user, work: work, convo: convo}
  end

  defp ask(convo, n) do
    for i <- 1..n, do: Chat.append(convo.id, "user", "question #{i}")
  end

  test "a fresh account has the full allowance", %{user: user} do
    assert Chat.remaining(user) == Chat.message_limit()
    assert Chat.allowed?(user)
  end

  test "only the writer's own questions count against it", %{user: user, convo: convo} do
    ask(convo, 3)
    Chat.append(convo.id, "assistant", "an answer, which is not a question")

    assert Chat.messages_sent(user.id) == 3
    assert Chat.remaining(user) == Chat.message_limit() - 3
  end

  test "it runs out, and does not go negative", %{user: user, convo: convo} do
    ask(convo, Chat.message_limit() + 5)

    assert Chat.remaining(user) == 0
    refute Chat.allowed?(user)
  end

  test "questions across every draft count together", %{user: user, convo: convo} do
    {:ok, other} = Works.create_work(user.id, %{"title" => "Other", "body" => String.duplicate("w ", 300)})
    {:ok, other_convo} = Chat.get_or_create_conversation(other.id)

    ask(convo, 4)
    ask(other_convo, 6)

    assert Chat.messages_sent(user.id) == 10
  end

  test "one account's questions do not count against another's", %{convo: convo} do
    ask(convo, 5)
    assert Chat.remaining(user_fixture()) == Chat.message_limit()
  end

  test "deleting a draft gives the questions back", %{user: user, work: work, convo: convo} do
    ask(convo, 7)
    assert Chat.messages_sent(user.id) == 7

    Works.delete_work(work)
    assert Chat.messages_sent(user.id) == 0
  end

  test "the owner of the deploy is not capped", %{convo: convo} do
    owner =
      user_fixture()
      |> Ecto.Changeset.change(email: Application.get_env(:marginalia, :owner_email))
      |> Marginalia.Repo.update!()

    {:ok, w} = Works.create_work(owner.id, %{"title" => "O", "body" => String.duplicate("w ", 300)})
    {:ok, c} = Chat.get_or_create_conversation(w.id)
    ask(c, Chat.message_limit() + 1)
    ask(convo, 1)

    assert Chat.remaining(owner) == :unlimited
    assert Chat.allowed?(owner)
  end
end
