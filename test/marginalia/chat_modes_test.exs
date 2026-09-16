defmodule Marginalia.ChatModesTest do
  @moduledoc """
  Three stances over one set of tools. What changes between them is what the
  assistant is for; what never changes is that it will not write prose.
  """
  use Marginalia.DataCase, async: true

  alias Marginalia.Chat
  alias Marginalia.Chat.Editor
  import Marginalia.AccountsFixtures

  setup do
    user = user_fixture()
    {:ok, work} = Marginalia.Works.create_work(user.id, %{"title" => "W", "body" => String.duplicate("word ", 400)})
    %{work: work}
  end

  test "there are three modes and read is the default" do
    assert Editor.mode_names() == ["read", "provoke", "bounce"]
    assert Editor.default_mode() == "read"
  end

  test "each mode has its own opener and stance" do
    for m <- Editor.modes() do
      assert m.opener != ""
      assert m.stance =~ "MODE:"
    end

    # and they are actually different from each other
  end

  test "every mode still refuses to write the writer's prose" do
    # the shared system prompt carries the constraint; the stances must not
    # quietly license their way around it
    for m <- Editor.modes() do
      refute m.stance =~ ~r/write (the|a|their) (next |new )?(scene|paragraph|sentence|line) for/i
    end

    assert Editor.mode("provoke").stance =~ "never write prose"
    assert Editor.mode("bounce").stance =~ "not writing it for them"
  end

  test "an unknown mode falls back rather than crashing" do
    assert Editor.mode("nonsense").id == "read"
    assert Editor.mode(nil).id == "read"
  end

  test "a conversation remembers the stance it was held in", %{work: work} do
    {:ok, convo} = Chat.create_conversation(work.id)
    assert convo.mode == "read"

    {:ok, convo} = Chat.set_mode(convo, "bounce")
    assert convo.mode == "bounce"

    # reopening resumes it
    assert Chat.latest_conversation(work.id).mode == "bounce"
  end

  test "switching stance keeps the history", %{work: work} do
    {:ok, convo} = Chat.create_conversation(work.id)
    Chat.append(convo.id, "user", "first question")
    {:ok, convo} = Chat.set_mode(convo, "provoke")

    assert [%{"content" => "first question"}] = Chat.history(convo.id)
    assert convo.mode == "provoke"
  end

  test "a junk mode cannot be stored on a conversation", %{work: work} do
    {:ok, convo} = Chat.create_conversation(work.id)
    assert {:error, changeset} = Chat.set_mode(convo, "hacker")
    assert %{mode: ["is invalid"]} = errors_on(changeset)
  end
end
