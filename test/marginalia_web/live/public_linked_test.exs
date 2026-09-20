defmodule MarginaliaWeb.PublicLinkedTest do
  @moduledoc """
  Pairs of drafts, and what runs between them, read by a stranger.

  The scoping tests are the ones that matter: this reads two drafts at once,
  so getting the owner check wrong exposes two people's work rather than one.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.{Links, Repo, Works}
  alias Marginalia.Links.LinkEdge

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})

    owner = user_fixture(%{email: Application.get_env(:marginalia, :owner_email)})
    stranger = user_fixture()

    body = "# H\n\n" <> String.duplicate("word ", 300)

    make = fn user, title ->
      {:ok, w} = Works.create_work(user.id, %{"title" => title, "body" => body})
      {:ok, w} = Works.set_status(w, "read")
      w
    end

    a = make.(owner, "The novel")
    b = make.(owner, "The story")
    theirs_a = make.(stranger, "Their first")
    theirs_b = make.(stranger, "Their second")

    node = fn w, title ->
      {:ok, n} =
        Works.insert_node(%{
          work_id: w.id,
          section_id: hd(Works.list_sections(w.id)).id,
          node_type: "beat",
          title: title,
          body: "b",
          quote: "word word word"
        })

      n
    end

    {:ok, link} = Links.get_or_create(a.id, b.id)

    Repo.insert!(%LinkEdge{
      link_id: link.id,
      from_id: node.(a, "He stops in the doorway").id,
      to_id: node.(b, "The unanswered question").id,
      edge_type: "pays_off",
      rationale: "Nine pays off the promise the story made."
    })

    {:ok, theirs} = Links.get_or_create(theirs_a.id, theirs_b.id)

    Repo.insert!(%LinkEdge{
      link_id: theirs.id,
      from_id: node.(theirs_a, "Private").id,
      to_id: node.(theirs_b, "Also private").id,
      edge_type: "develops"
    })

    {:ok, empty} = Links.get_or_create(b.id, make.(owner, "Unrelated").id)

    %{link: link, theirs: theirs, empty: empty}
  end

  test "a stranger sees the pair and its edges", ctx do
    {:ok, _view, html} = live(build_conn(), ~p"/linked/#{ctx.link.id}")

    assert html =~ "The novel"
    assert html =~ "The story"
    assert html =~ "He stops in the doorway"
    assert html =~ "pays off"
    assert html =~ "Nine pays off the promise the story made."
  end

  test "somebody else's pair is not readable", ctx do
    assert {:error, {:live_redirect, %{to: "/linked"}}} =
             live(build_conn(), ~p"/linked/#{ctx.theirs.id}")

    assert Links.public_link(ctx.theirs.id) == nil
  end

  test "a pair that found nothing is not offered", ctx do
    assert Links.public_link(ctx.empty.id) == nil

    {:ok, _view, html} = live(build_conn(), ~p"/linked")
    refute html =~ "Unrelated"
  end

  test "the index lists the owner's pairs only", ctx do
    {:ok, _view, html} = live(build_conn(), ~p"/linked")

    assert html =~ "The novel"
    refute html =~ "Their first"
    assert html =~ "1 edges" or html =~ "1 edge"
    assert ctx.link.id
  end

  test "it carries no control that writes", ctx do
    {:ok, _view, html} = live(build_conn(), ~p"/linked/#{ctx.link.id}")

    for control <- ~w(make pick relink edit_block suggest_rewrite) do
      refute html =~ ~s(phx-click="#{control}")
    end
  end
end
