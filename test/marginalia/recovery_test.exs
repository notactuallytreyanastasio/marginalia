defmodule Marginalia.RecoveryTest do
  @moduledoc """
  A deploy went out while twelve links were running. Every one of them died
  with the container and every row went on saying "linking" for ever.
  """
  use Marginalia.DataCase, async: false

  import Marginalia.AccountsFixtures

  alias Marginalia.{Links, Recovery, Works}

  setup do
    user = user_fixture()

    mk = fn t ->
      {:ok, w} =
        Works.create_work(user.id, %{"title" => t, "body" => String.duplicate("word ", 300)})

      w
    end

    %{a: mk.("One"), b: mk.("Two"), c: mk.("Three")}
  end

  test "a link left mid-run is marked failed, with the reason", %{a: a, b: b} do
    {:ok, link} = Links.get_or_create(a.id, b.id)
    {:ok, _} = Links.set_status(link, "linking")

    assert {1, _} = Recovery.sweep()

    link = Links.get(link.id)
    assert link.status == "failed"
    assert link.error =~ "restart"
  end

  test "a read left mid-run is too", %{c: c} do
    {:ok, _} = Works.set_status(c, "reading")

    assert {_, 1} = Recovery.sweep()
    assert Repo.reload!(c).status == "failed"
  end

  test "it leaves finished work alone", %{a: a, b: b, c: c} do
    {:ok, link} = Links.get_or_create(a.id, b.id)
    {:ok, _} = Links.set_status(link, "linked", %{summary: "Done."})
    {:ok, _} = Works.set_status(c, "read")

    assert {0, 0} = Recovery.sweep()

    assert Links.get(link.id).status == "linked"
    assert Links.get(link.id).summary == "Done."
    assert Repo.reload!(c).status == "read"
  end

  test "nothing in flight is a no-op" do
    assert {0, 0} = Recovery.sweep()
  end
end
