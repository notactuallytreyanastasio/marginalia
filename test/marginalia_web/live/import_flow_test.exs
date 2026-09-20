defmodule MarginaliaWeb.ImportFlowTest do
  @moduledoc """
  The bulk import, end to end, with GitHub stubbed out.

  What is under test is the flow: that listing is a separate step from
  importing, that nothing is created until somebody has seen the list, and
  that the three ways of choosing — a search, a title regex, the boxes —
  compose instead of fighting. None of that is about HTTP, and a test that
  needed a token would not run.

  The stub is deliberately dumb. It answers with fixed rows and records what
  it was asked for, because the questions worth asking here are "was the
  right set carried from the choosing step to the import step" and "what
  does the page do when one of them cannot be fetched".
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.Works

  defmodule FakeHub do
    @moduledoc false

    @rows [
      %{number: 9, title: "Fix the parser", state: "merged", draft: false},
      %{number: 8, title: "Revert the fix", state: "open", draft: false},
      %{number: 7, title: "Add a test", state: "closed", draft: true},
      %{number: 6, title: "Nothing to do with it", state: "open", draft: false}
    ]

    def rows, do: @rows

    def list(owner, repo, _token, _opts \\ []) do
      {:ok, Enum.map(@rows, &row("#{owner}/#{repo}", &1))}
    end

    def search(query, token, opts \\ [])
    def search("boom" <> _, _token, _opts), do: {:error, :forbidden}

    def search(_query, _token, _opts) do
      {:ok, Enum.map(@rows, &row("found/elsewhere", &1))}
    end

    # #7 is the one that cannot be fetched, so every test has a named
    # failure available without arranging one
    def documents(candidates, _token, opts \\ []) do
      total = length(candidates)

      {bad, good} = Enum.split_with(candidates, &(&1.number == 7))

      docs =
        Enum.map(good, fn c ->
          if is_function(opts[:on_item]), do: opts[:on_item].(c, total)

          %{
            number: c.number,
            repo: c.repo,
            title: c.title,
            body: "# #{c.title}\n\n" <> String.duplicate("word ", 80),
            source_url: c.url
          }
        end)

      %{documents: docs, failed: Enum.map(bad, &{&1, :not_found})}
    end

    defp row(repo, r) do
      %{
        repo: repo,
        number: r.number,
        title: r.title,
        url: "https://example.invalid/#{repo}/pull/#{r.number}",
        state: r.state,
        draft: r.draft,
        base: "main",
        head: "b#{r.number}",
        updated_at: "2026-01-01T00:00:00Z"
      }
    end
  end

  setup %{conn: conn} do
    previous = Application.get_env(:marginalia, :github_api)
    Application.put_env(:marginalia, :github_api, FakeHub)
    on_exit(fn -> Application.put_env(:marginalia, :github_api, previous) end)

    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  defp to_listing(view) do
    render_click(view, "source", %{"to" => "github"})
    render_submit(view, "find", %{"mode" => "repo", "repo" => "temper/blimp", "token" => "t"})
    render_async(view)
  end

  test "the first step is a choice of source, and creates nothing", %{conn: conn, user: user} do
    {:ok, _view, html} = live(conn, ~p"/import")

    assert html =~ "Pull requests"
    assert html =~ "Files"
    assert Works.list_works(user.id) == []
  end

  test "finding lists the pull requests without importing any", %{conn: conn, user: user} do
    {:ok, view, _} = live(conn, ~p"/import")
    html = to_listing(view)

    for row <- FakeHub.rows(), do: assert(html =~ row.title)
    assert html =~ "<b>4 selected</b>"

    # the whole point of the step: a listing is not an import
    assert Works.list_works(user.id) == []
  end

  test "a title regex filters the list and sets the selection", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/import")
    to_listing(view)

    html = render_change(view, "pattern", %{"pattern" => "fix"})

    assert html =~ "Fix the parser"
    assert html =~ "Revert the fix"
    refute html =~ "Nothing to do with it"
    assert html =~ "<b>2 selected</b>"
  end

  test "a pattern that will not compile says so and keeps the list", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/import")
    to_listing(view)

    html = render_change(view, "pattern", %{"pattern" => "(unclosed"})

    assert html =~ "Fix the parser", "a half-typed pattern should not empty the page"
    assert html =~ "missing closing parenthesis" or html =~ "unmatched"
  end

  test "the boxes have the last word over the regex", %{conn: conn, user: user} do
    {:ok, view, _} = live(conn, ~p"/import")
    to_listing(view)

    render_change(view, "pattern", %{"pattern" => "fix"})
    # put one back that the pattern did not match
    render_click(view, "toggle", %{"key" => "temper/blimp#6"})
    render_change(view, "settings", %{"folder" => "Picked", "commits" => "false"})
    render_submit(view, "import", %{})
    render_async(view)

    titles = user.id |> Works.list_works() |> Enum.map(& &1.title) |> Enum.sort()
    assert titles == ["Fix the parser", "Nothing to do with it", "Revert the fix"]
  end

  test "clearing and selecting work on what is shown, not on everything", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/import")
    to_listing(view)

    render_change(view, "pattern", %{"pattern" => "fix"})
    assert render_click(view, "none", %{}) =~ "<b>0 selected</b>"

    # "all" means all *shown*, so the two the pattern hid stay out
    assert render_click(view, "all", %{}) =~ "<b>2 selected</b>"
  end

  test "importing lands them in a folder and says what could not be fetched", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _} = live(conn, ~p"/import")
    to_listing(view)

    render_change(view, "settings", %{"folder" => "temper/blimp", "commits" => "true"})
    render_submit(view, "import", %{})
    html = render_async(view)

    assert html =~ "3 drafts imported"
    assert html =~ "Could not be fetched"
    assert html =~ "Add a test"

    works = Works.list_works(user.id)
    assert length(works) == 3
    assert Enum.all?(works, &(&1.folder_id != nil))
    refute Enum.any?(works, &(&1.title == "Add a test"))
  end

  test "a second import into the same folder skips what is there", %{conn: conn, user: user} do
    run = fn ->
      {:ok, view, _} = live(conn, ~p"/import")
      to_listing(view)
      render_change(view, "settings", %{"folder" => "temper/blimp"})
      render_submit(view, "import", %{})
      render_async(view)
    end

    run.()
    html = run.()

    assert html =~ "0 drafts imported" or html =~ "already in the folder"
    assert length(Works.list_works(user.id)) == 3
  end

  test "a search that GitHub refuses is reported in words", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/import")
    render_click(view, "source", %{"to" => "github"})

    render_submit(view, "find", %{"mode" => "search", "query" => "boom", "token" => "t"})
    html = render_async(view)

    assert html =~ "GitHub refused"
    refute html =~ "Fix the parser"
  end

  test "a search lists across repositories", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/import")
    render_click(view, "source", %{"to" => "github"})

    render_submit(view, "find", %{"mode" => "search", "query" => "label:design", "token" => "t"})
    html = render_async(view)

    assert html =~ "found/elsewhere"
    assert html =~ "Fix the parser"
  end

  test "a repository written wrongly is refused before any request", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/import")
    render_click(view, "source", %{"to" => "github"})

    html = render_submit(view, "find", %{"mode" => "repo", "repo" => "blimp", "token" => "t"})

    assert html =~ "owner/name"
  end

  test "the token is never rendered back into the page", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/import")
    render_click(view, "source", %{"to" => "github"})

    render_submit(view, "find", %{
      "mode" => "repo",
      "repo" => "temper/blimp",
      "token" => "ghp_secret_do_not_print"
    })

    html = render_async(view)
    refute html =~ "ghp_secret_do_not_print"

    render_change(view, "settings", %{"folder" => "x"})
    render_submit(view, "import", %{})
    refute render_async(view) =~ "ghp_secret_do_not_print"
  end

  test "the file step is reachable and starts empty", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/import")
    html = render_click(view, "source", %{"to" => "files"})

    assert html =~ "Drop up to"
    assert html =~ "Import 0"
  end

  test "back walks the steps rather than reloading", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/import")
    to_listing(view)

    assert render_click(view, "back", %{}) =~ "GitHub token"
    assert render_click(view, "back", %{}) =~ "Pull requests"
  end
end
