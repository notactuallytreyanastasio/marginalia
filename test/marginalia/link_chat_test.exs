defmodule Marginalia.LinkChatTest do
  @moduledoc """
  The conversation about a pair: where it lives, and what it is handed.
  """
  use Marginalia.DataCase, async: true

  import Marginalia.AccountsFixtures

  alias Marginalia.{Links, Works}
  alias Marginalia.Links.Chat, as: LinkChat
  alias Marginalia.Chat.Conversation

  setup do
    user = user_fixture()

    make = fn title ->
      body =
        "# #{title}\n\nA sentence long enough to make a section of it.\n\n" <>
          String.duplicate("word ", 200)

      {:ok, w} = Works.create_work(user.id, %{"title" => title, "body" => body})
      {:ok, w} = Works.set_status(w, "read")
      s = hd(Works.list_sections(w.id))

      {:ok, n} =
        Works.insert_node(%{
          work_id: w.id,
          section_id: s.id,
          node_type: "beat",
          title: "a beat in #{title}",
          quote: "A sentence long enough"
        })

      {w, n}
    end

    {a, an} = make.("First")
    {b, bn} = make.("Second")
    {:ok, link} = Links.get_or_create(a.id, b.id)
    {:ok, link} = Links.set_status(link, "linked", %{summary: "B answers A."})

    Links.store_edges(
      link,
      [
        %{
          "from" => an.id,
          "to" => bn.id,
          "type" => "tension",
          "why" => "They pull apart on pace."
        }
      ],
      Marginalia.Analysis.Linker.types()
    )

    %{link: link, a: a, b: b}
  end

  describe "where it lives" do
    test "a conversation belongs to the link, not to either draft", %{link: link} do
      {:ok, convo} = LinkChat.conversation(link)

      assert convo.link_id == link.id
      assert is_nil(convo.work_id)
      assert convo.anchor_kind == "link"
    end

    test "asking twice returns the same one, so the state survives closing", %{link: link} do
      {:ok, one} = LinkChat.conversation(link)
      LinkChat.append(one, "user", "does it hold up?")
      {:ok, two} = LinkChat.conversation(link)

      assert one.id == two.id
      assert [%{"role" => "user", "content" => "does it hold up?"}] = LinkChat.history(two)
    end

    test "a conversation cannot belong to both a draft and a link", %{link: link, a: a} do
      assert {:error, changeset} =
               %Conversation{}
               |> Conversation.changeset(%{work_id: a.id, link_id: link.id})
               |> Repo.insert()

      assert "a conversation belongs to one or the other, not both" in errors_on(changeset).work_id
    end

    test "or to neither" do
      assert {:error, changeset} = %Conversation{} |> Conversation.changeset(%{}) |> Repo.insert()
      assert "a conversation belongs to a draft or to a link" in errors_on(changeset).work_id
    end

    test "deleting a draft takes the link's conversation with it", %{link: link, a: a} do
      {:ok, _convo} = LinkChat.conversation(link)
      Repo.delete!(a)

      assert Repo.get_by(Conversation, link_id: link.id) == nil
    end
  end

  describe "what it is handed" do
    test "both maps, every edge, and the reason each was drawn", %{link: link} do
      card = LinkChat.card(link)

      assert card =~ "First"
      assert card =~ "Second"
      assert card =~ "B answers A."
      assert card =~ "--tension-->"
      assert card =~ "They pull apart on pace."
      # the anchored sentence travels with the node, so it can be quoted
      assert card =~ "A sentence long enough"
    end

    test "the sides are labelled, so it can tell which document is which", %{link: link} do
      card = LinkChat.card(link)
      assert card =~ "A:"
      assert card =~ "B:"
      assert card =~ "# MAP OF A"
      assert card =~ "# MAP OF B"
    end

    test "the prompt forbids the things the product does not do" do
      p = LinkChat.prompt()

      assert p =~ "do not write prose"
      assert p =~ "do not rank them"
      # and the discipline that makes it worth reading
      assert p =~ "An edge you were not given does not exist"
    end
  end

  describe "the reply" do
    test "only text is ever stored — a message map is not a reply", %{link: link} do
      {:ok, convo} = LinkChat.conversation(link)

      # LLM.chat returns the whole message; appending that map instead of its
      # text failed the insert quietly and the answer never appeared
      assert_raise FunctionClauseError, fn ->
        LinkChat.append(convo, "assistant", %{"role" => "assistant", "content" => "hi"})
      end

      assert {:ok, _} = LinkChat.append(convo, "assistant", "hi")
      assert [%{"content" => "hi"}] = LinkChat.history(convo)
    end
  end
end
