defmodule Marginalia.ClustersTest do
  @moduledoc """
  Links are pairs; pairs chain. This is the grouping that makes a chain
  visible, and the gap in it findable.
  """
  use Marginalia.DataCase, async: true

  import Marginalia.AccountsFixtures

  alias Marginalia.{Links, Works}

  setup do
    user = user_fixture()

    make = fn title ->
      body =
        "# #{title}\n\nA sentence long enough for a section.\n\n" <>
          String.duplicate("word ", 200)

      {:ok, w} = Works.create_work(user.id, %{"title" => title, "body" => body})
      {:ok, w} = Works.set_status(w, "read")
      w
    end

    %{
      user: user,
      one: make.("One"),
      two: make.("Two"),
      three: make.("Three"),
      far: make.("Unrelated")
    }
  end

  test "a chain of three is one group, not three pairs", %{user: u, one: a, two: b, three: c} do
    {:ok, _} = Links.get_or_create(a.id, b.id)
    {:ok, _} = Links.get_or_create(b.id, c.id)

    assert [cluster] = Links.clusters(u.id)

    assert Enum.map(cluster.works, & &1.title) |> Enum.sort() ==
             ["Three", "Two", "One"] |> Enum.sort()

    assert length(cluster.links) == 2
  end

  test "the pair nobody has related yet is named", %{user: u, one: a, two: b, three: c} do
    # 1↔2 and 2↔3, so 1↔3 is the obvious next question and nothing else in
    # the product would ever raise it
    {:ok, _} = Links.get_or_create(a.id, b.id)
    {:ok, _} = Links.get_or_create(b.id, c.id)

    [cluster] = Links.clusters(u.id)
    assert [{x, y}] = cluster.missing
    assert Enum.sort([x.title, y.title]) == ["One", "Three"]
  end

  test "once all three are related there is no gap left", %{user: u, one: a, two: b, three: c} do
    {:ok, _} = Links.get_or_create(a.id, b.id)
    {:ok, _} = Links.get_or_create(b.id, c.id)
    {:ok, _} = Links.get_or_create(a.id, c.id)

    assert [%{missing: [], links: links}] = Links.clusters(u.id)
    assert length(links) == 3
  end

  test "drafts that are not reachable from each other stay apart", %{
    user: u,
    one: a,
    two: b,
    three: c,
    far: d
  } do
    {:ok, _} = Links.get_or_create(a.id, b.id)
    {:ok, _} = Links.get_or_create(c.id, d.id)

    groups = Links.clusters(u.id)
    assert length(groups) == 2
    assert Enum.all?(groups, &(length(&1.works) == 2))
  end

  test "the biggest group comes first, so the page leads with the real body of work",
       %{user: u, one: a, two: b, three: c, far: d} do
    {:ok, _} = Links.get_or_create(c.id, d.id)
    {:ok, _} = Links.get_or_create(a.id, b.id)
    {:ok, _} = Links.get_or_create(b.id, c.id)

    assert [big | _] = Links.clusters(u.id)
    assert length(big.works) == 4
  end

  test "one writer's constellations never include another's", %{user: u, one: a, two: b} do
    {:ok, _} = Links.get_or_create(a.id, b.id)

    theirs = user_fixture()

    {:ok, x} =
      Works.create_work(theirs.id, %{"title" => "X", "body" => String.duplicate("word ", 300)})

    {:ok, y} =
      Works.create_work(theirs.id, %{"title" => "Y", "body" => String.duplicate("word ", 300)})

    {:ok, _} = Links.get_or_create(x.id, y.id)

    assert [%{works: works}] = Links.clusters(u.id)
    refute Enum.any?(works, &(&1.title in ["X", "Y"]))
  end
end
