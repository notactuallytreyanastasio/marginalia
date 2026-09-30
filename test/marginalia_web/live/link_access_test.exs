defmodule MarginaliaWeb.LinkAccessTest do
  @moduledoc """
  Who may read a pair.

  A link renders both of its drafts whole, and link ids count up from one.
  A draft is private behind a slug nobody can guess, so a link page that
  loaded any id handed every writer's work to anybody with a guest session
  who could count.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.{Links, Works}

  setup %{conn: conn} do
    Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})

    previous = Application.get_env(:marginalia, :deepseek_api_key)
    Application.put_env(:marginalia, :deepseek_api_key, nil)
    on_exit(fn -> Application.put_env(:marginalia, :deepseek_api_key, previous) end)

    writer = user_fixture()
    stranger = user_fixture()

    make = fn user, title ->
      body = "# #{title}\n\nA private sentence in #{title}.\n\n" <> String.duplicate("word ", 200)
      {:ok, w} = Works.create_work(user.id, %{"title" => title, "body" => body})
      {:ok, w} = Works.set_status(w, "read")
      w
    end

    a = make.(writer, "Mine one")
    b = make.(writer, "Mine two")
    {:ok, link} = Links.get_or_create(a.id, b.id)

    %{
      writer: writer,
      stranger: stranger,
      a: a,
      b: b,
      link: link,
      theirs: make.(stranger, "Theirs"),
      writer_conn: log_in_user(conn, writer),
      stranger_conn: log_in_user(build_conn(), stranger)
    }
  end

  test "the writer reads their own pair", %{writer_conn: conn, link: link} do
    {:ok, _view, html} = live(conn, ~p"/links/#{link.id}")
    assert html =~ "Mine one <span class=\"x\">↔</span> Mine two"
  end

  test "somebody else is turned away, and sees neither draft",
       %{stranger_conn: conn, link: link} do
    assert {:error, {:live_redirect, %{to: "/works"}}} = live(conn, ~p"/links/#{link.id}")
    assert {:error, {:live_redirect, %{to: "/works"}}} = live(conn, ~p"/links/#{link.id}/read")
  end

  test "a malformed id is a miss, not a crash", %{writer_conn: conn} do
    assert {:error, {:live_redirect, %{to: "/works"}}} = live(conn, "/links/nope")
  end

  test "a pair cannot be made from somebody else's draft",
       %{writer_conn: conn, a: a, theirs: theirs} do
    {:ok, view, _html} = live(conn, ~p"/links")

    html = render_click(view, "make", %{"a" => to_string(a.id), "b" => to_string(theirs.id)})

    assert html =~ "Pick two different drafts."
    refute Links.get_for(a.id, theirs.id)
  end

  test "the pass reporting its stages does not take the page down",
       %{writer_conn: conn, link: link} do
    {:ok, view, _html} = live(conn, ~p"/links/#{link.id}")

    for stage <- [:reading, :asking, :checking] do
      Phoenix.PubSub.broadcast(Marginalia.PubSub, "link:#{link.id}", {:link, :stage, stage})
    end

    assert render(view) =~ "Mine one <span class=\"x\">↔</span> Mine two"
  end

  test "two callers racing to make one pair both get the same row", %{a: a, theirs: theirs} do
    {:ok, other} = Works.create_work(a.user_id, %{"title" => "Third", "body" => "# T\n\nText."})

    results =
      1..4
      |> Enum.map(fn _ -> Task.async(fn -> Links.get_or_create(a.id, other.id) end) end)
      |> Task.await_many()

    ids = for {:ok, link} <- results, uniq: true, do: link.id
    assert length(ids) == 1
    refute Links.get_for(a.id, theirs.id)
  end
end
