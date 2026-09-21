defmodule Marginalia.LinksTest do
  @moduledoc """
  The linking graph, and the check that makes it worth reading.

  An edge between two manuscripts is a claim about both of them. The model
  proposes them by id, and this is where a proposal that cannot be true gets
  thrown away before anyone sees it.
  """
  use Marginalia.DataCase, async: true

  import Marginalia.AccountsFixtures

  alias Marginalia.{Links, Works}
  alias Marginalia.Analysis.Linker

  setup do
    user = user_fixture()

    make = fn title, body ->
      {:ok, w} = Works.create_work(user.id, %{"title" => title, "body" => body})
      {:ok, w} = Works.set_status(w, "read")
      s = hd(Works.list_sections(w.id))

      {:ok, n} =
        Works.insert_node(%{
          work_id: w.id,
          section_id: s.id,
          node_type: "beat",
          title: "a beat in " <> title,
          quote: "a sentence"
        })

      {w, n}
    end

    {a, a_node} =
      make.(
        "First",
        "# One\n\nA sentence that is long enough to be a section.\n\n" <>
          String.duplicate("word ", 200)
      )

    {b, b_node} =
      make.(
        "Second",
        "# Two\n\nAnother sentence that is long enough here.\n\n" <>
          String.duplicate("word ", 200)
      )

    {c, c_node} =
      make.(
        "Third",
        "# Three\n\nA third sentence, also long enough for this.\n\n" <>
          String.duplicate("word ", 200)
      )

    {:ok, link} = Links.get_or_create(a.id, b.id)
    %{a: a, b: b, c: c, a_node: a_node, b_node: b_node, c_node: c_node, link: link}
  end

  describe "the pair" do
    test "is unordered — linking A to B is the same row as B to A", %{a: a, b: b, link: link} do
      assert {:ok, same} = Links.get_or_create(b.id, a.id)
      assert same.id == link.id
      assert Links.get_for(b.id, a.id).id == link.id
    end

    test "a work cannot be linked to itself", %{a: a} do
      assert {:error, :same_work} = Links.get_or_create(a.id, a.id)
    end

    test "it shows up from either side", %{a: a, b: b, link: link} do
      assert Links.for_work(a.id) |> Enum.map(& &1.id) == [link.id]
      assert Links.for_work(b.id) |> Enum.map(& &1.id) == [link.id]
    end

    test "the other side is named from whichever end you stand at", %{a: a, b: b, link: link} do
      link = Marginalia.Repo.preload(link, [:a_work, :b_work])
      assert Links.other(link, a.id).id == b.id
      assert Links.other(link, b.id).id == a.id
    end
  end

  describe "storing what the model proposed" do
    test "a good edge is kept, with its reason", %{link: link, a_node: a_node, b_node: b_node} do
      proposed = [
        %{
          "from" => a_node.id,
          "to" => b_node.id,
          "type" => "answers",
          "why" => "It replies to the claim."
        }
      ]

      assert {1, 0} = Links.store_edges(link, proposed, Linker.types())
      assert [edge] = Links.edges(link)
      assert edge.edge_type == "answers"
      assert edge.rationale == "It replies to the claim."
      assert edge.from.id == a_node.id
      assert edge.to.id == b_node.id
    end

    test "an edge inside ONE manuscript is dropped", %{link: link, a_node: a_node, a: a} do
      # the failure that would make the whole feature a lie: an internal edge
      # presented as a relationship between the two documents
      {:ok, other} =
        Works.insert_node(%{
          work_id: a.id,
          node_type: "spine",
          title: "elsewhere in the same draft"
        })

      proposed = [
        %{"from" => a_node.id, "to" => other.id, "type" => "develops", "why" => "Both in A."}
      ]

      assert {0, 1} = Links.store_edges(link, proposed, Linker.types())
      assert Links.edges(link) == []
    end

    test "an invented id is dropped", %{link: link, a_node: a_node} do
      proposed = [
        %{
          "from" => a_node.id,
          "to" => 999_999,
          "type" => "develops",
          "why" => "Points at nothing."
        }
      ]

      assert {0, 1} = Links.store_edges(link, proposed, Linker.types())
    end

    test "an id from a third manuscript is dropped", %{link: link, a_node: a_node, c_node: c_node} do
      proposed = [
        %{
          "from" => a_node.id,
          "to" => c_node.id,
          "type" => "develops",
          "why" => "Reaches outside the pair."
        }
      ]

      assert {0, 1} = Links.store_edges(link, proposed, Linker.types())
    end

    test "an unknown relation is dropped", %{link: link, a_node: a_node, b_node: b_node} do
      proposed = [
        %{
          "from" => a_node.id,
          "to" => b_node.id,
          "type" => "vibes_with",
          "why" => "Not a relation."
        }
      ]

      assert {0, 1} = Links.store_edges(link, proposed, Linker.types())
    end

    test "an edge with no reason is dropped — the reason is the product", %{
      link: link,
      a_node: a_node,
      b_node: b_node
    } do
      proposed = [
        %{"from" => a_node.id, "to" => b_node.id, "type" => "develops", "why" => "   "},
        %{"from" => b_node.id, "to" => a_node.id, "type" => "develops"}
      ]

      assert {0, 2} = Links.store_edges(link, proposed, Linker.types())
    end

    test "string ids are accepted, because models return both", %{
      link: link,
      a_node: a_node,
      b_node: b_node
    } do
      proposed = [
        %{
          "from" => to_string(a_node.id),
          "to" => to_string(b_node.id),
          "type" => "echoes",
          "why" => "Same move."
        }
      ]

      assert {1, 0} = Links.store_edges(link, proposed, Linker.types())
    end

    test "the same edge twice is stored once", %{link: link, a_node: a_node, b_node: b_node} do
      e = %{"from" => a_node.id, "to" => b_node.id, "type" => "develops", "why" => "Once."}
      assert {1, 0} = Links.store_edges(link, [e, e], Linker.types())
      assert length(Links.edges(link)) == 1
    end

    test "the edge count is capped", %{link: link, a_node: a_node, b_node: b_node, b: b} do
      extra =
        for i <- 1..80 do
          {:ok, n} = Works.insert_node(%{work_id: b.id, node_type: "beat", title: "beat #{i}"})
          %{"from" => a_node.id, "to" => n.id, "type" => "develops", "why" => "Reason #{i}."}
        end

      {kept, _} = Links.store_edges(link, extra, Linker.types(), 10)
      assert kept == 10
      assert length(Links.edges(link)) == 10
      assert b_node.id
    end

    test "re-linking replaces rather than accumulates", %{
      link: link,
      a_node: a_node,
      b_node: b_node
    } do
      Links.store_edges(
        link,
        [%{"from" => a_node.id, "to" => b_node.id, "type" => "develops", "why" => "First."}],
        Linker.types()
      )

      Links.clear_edges(link)

      Links.store_edges(
        link,
        [%{"from" => a_node.id, "to" => b_node.id, "type" => "tension", "why" => "Second."}],
        Linker.types()
      )

      assert [edge] = Links.edges(link)
      assert edge.edge_type == "tension"
    end
  end

  describe "the vocabulary" do
    test "is the one a reader already knows, minus what cannot cross" do
      # `realises` and `asks_about` are about a node's place in its OWN
      # document's spine, so they are meaningless between two
      refute "realises" in Linker.types()
      refute "asks_about" in Linker.types()

      for t <- ~w(develops pays_off requires tension), do: assert(t in Linker.types())
    end

    test "every relation in the vocabulary is described in the prompt" do
      for t <- Linker.types(), do: assert(Linker.prompt() =~ t)
    end

    test "the prompt forbids the same-document edge in words, as well as in code" do
      assert Linker.prompt() =~ "one end in manuscript A and the other in manuscript B"
    end
  end

  describe "stats" do
    test "count both the edges and how much of each side they touch", %{
      link: link,
      a_node: a_node,
      b_node: b_node
    } do
      Links.store_edges(
        link,
        [%{"from" => a_node.id, "to" => b_node.id, "type" => "answers", "why" => "Because."}],
        Linker.types()
      )

      s = Links.stats(link)
      assert s.edges == 1
      assert s.by_type == %{"answers" => 1}
      assert s.a_nodes == 1
      assert s.b_nodes == 1
    end
  end

  describe "calling the documents by their names" do
    setup %{a: a, b: b} do
      # A numbered stack title, and one whose own text starts with "A " —
      # between them they are every way this has gone wrong.
      {:ok, a} = Works.update_work(a, %{"title" => "1. A page with no script on it"})
      {:ok, b} = Works.update_work(b, %{"title" => "2. The backend scaffold"})
      {:ok, link} = Links.get_or_create(a.id, b.id)
      %{link: link}
    end

    test "a title beginning with a digit keeps its number", %{link: link} do
      out = Links.plain("runner. B answers it.", link)

      # Built as `"\\1" <> "2. The backend scaffold"`, the replacement reads
      # as backreference 12 — which does not exist, so it expanded to nothing
      # and took the chapter number and the captured space with it.
      assert out =~ "2. The backend scaffold",
             "the chapter number was eaten by a backreference nobody wrote"

      refute out =~ "runner.. ",
             "the captured whitespace went with it, doubling the full stop"
    end

    test "a title is never substituted into a second time", %{link: link} do
      out = Links.plain("B answers A's open question.", link)

      # Six sequential replaces meant a title inserted early was ordinary
      # English by the time a later pass read it, and "A page" inside it got
      # substituted again. One pass resumes after the match it just made.
      assert out == "2. The backend scaffold answers 1. A page with no script on it's open question."

      refute out =~ "1. 1.", "the title was spliced through itself"
    end

    test "a possessive letter is resolved wherever it appears", %{link: link} do
      out = Links.plain("It sits downstream of A's grammar.", link)

      # English has no possessive indefinite article, so "A's" is never the
      # word "a" and needs no sentence-start to be safe.
      assert out =~ "1. A page with no script on it's grammar"
    end

    test "the full form is resolved and loses the word Manuscript", %{link: link} do
      out = Links.plain("Manuscript B extends Manuscript A.", link)

      assert out == "2. The backend scaffold extends 1. A page with no script on it."
      refute out =~ "Manuscript"
    end

    test "a bare letter mid-sentence is left alone, and so is the article", %{link: link} do
      # "Part A" is the reason this is not a plain word replacement, and
      # "A page" is the reason it can never become one: telling the label
      # from the article needs to know whether the next word is a verb.
      assert Links.plain("See Part A and Exhibit B.", link) =~ "Part A and Exhibit B"

      refute Links.plain("It extends B.", link) =~ "2. The backend scaffold",
             "a bare letter mid-sentence could be anything"
    end

    test "the summary goes through the same substitution", %{link: link} do
      {:ok, link} = Links.set_status(link, "linked", %{summary: "B develops it. A is upstream."})

      assert Links.summary(link) =~ "2. The backend scaffold"
      assert Links.summary(link) =~ "1. A page with no script on it"
    end
  end
end
