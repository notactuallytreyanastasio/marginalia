defmodule MarginaliaWeb.ConfirmGateTest do
  @moduledoc """
  The page a draft lands on before anything has been read.

  A stranger uploaded thirty thousand words and it sat unread for two
  days. The read is a button they have to press, and the button was under
  the section list — twenty-five rows of it, which is about eight hundred
  pixels, which is under the fold. The one draft nobody ran was the one
  with the most sections, which is exactly what pushed the button down.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.Works

  setup %{conn: conn} do
    Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})

    # the gate only offers the read when a key is configured; without one
    # it correctly says so instead, which is a different test
    previous = Application.get_env(:marginalia, :deepseek_api_key)
    Application.put_env(:marginalia, :deepseek_api_key, "test-key")
    on_exit(fn -> Application.put_env(:marginalia, :deepseek_api_key, previous) end)

    user = user_fixture()

    make = fn sections ->
      body =
        Enum.map_join(1..sections, "\n\n", fn i ->
          "# Part #{i}\n\n" <> String.duplicate("word ", 300)
        end)

      {:ok, w} = Works.create_work(user.id, %{"title" => "A long draft", "body" => body})
      w
    end

    %{conn: log_in_user(conn, user), make: make}
  end

  defp gate(html) do
    [_, inner] = Regex.run(~r/Before it reads(.*?)(?:<\/div>\s*<\/div>|\z)/s, html)
    inner
  end

  test "the read can be started before the list of sections", %{conn: conn, make: make} do
    w = make.(25)
    {:ok, _view, html} = live(conn, ~p"/works/#{w.slug}")

    assert html =~ "Read it — 25 sections"

    inner = gate(html)
    button = :binary.match(inner, "Read it —") |> elem(0)
    list = :binary.match(inner, ~s(class="mg-rows)) |> elem(0)

    assert button < list,
           "the only way to start a read is underneath twenty-five rows of section list"
  end

  test "a long draft offers it at the bottom too", %{conn: conn, make: make} do
    w = make.(25)
    {:ok, _view, html} = live(conn, ~p"/works/#{w.slug}")

    assert length(Regex.scan(~r/Read it — 25 sections/, html)) == 2
  end

  test "a short draft does not repeat itself", %{conn: conn, make: make} do
    w = make.(3)
    {:ok, _view, html} = live(conn, ~p"/works/#{w.slug}")

    assert length(Regex.scan(~r/Read it — 3 sections/, html)) == 1
  end

  test "pressing it starts the read", %{conn: conn, make: make} do
    w = make.(3)
    {:ok, view, _html} = live(conn, ~p"/works/#{w.slug}")

    html = view |> element("button", "Read it — 3 sections") |> render_click()

    assert html =~ "Reading your draft"
    assert Marginalia.Repo.reload!(w).status in ["reading", "failed", "read"]
  end

  test "with no key it says so rather than offering a button", %{conn: conn, make: make} do
    Application.put_env(:marginalia, :deepseek_api_key, nil)
    w = make.(4)

    {:ok, _view, html} = live(conn, ~p"/works/#{w.slug}")

    refute html =~ "Read it —"
    assert html =~ "key is configured on this deploy"
  end

  test "someone else's draft offers no button at all", %{make: make} do
    w = make.(4)
    {:ok, _view, html} = live(build_conn(), ~p"/works/#{w.slug}")

    refute html =~ "Read it —"
  end
end
