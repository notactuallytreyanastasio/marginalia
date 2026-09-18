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

  describe "it is not kept" do
    test "the module offers no way to store a turn" do
      # the turns live in the LiveView and die with it: this is a
      # conversation about a shape, and the shape changes whenever either
      # draft is re-read or the pair is linked again
      refute function_exported?(LinkChat, :append, 3)
      refute function_exported?(LinkChat, :history, 1)
      refute function_exported?(LinkChat, :conversation, 1)
    end

    test "and a conversation row still has to belong to a draft" do
      assert {:error, changeset} =
               %Conversation{} |> Conversation.changeset(%{}) |> Repo.insert()

      assert "can't be blank" in errors_on(changeset).work_id
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
end
