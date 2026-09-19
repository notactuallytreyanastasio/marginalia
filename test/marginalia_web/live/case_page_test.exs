defmodule MarginaliaWeb.CasePageTest do
  @moduledoc """
  The case page: it renders, and the connections can be sliced.

  There was no test for this page at all, and it shipped raising
  BadBooleanError on every load — `@q != "" or @kind or @pair`, where a nil
  filter is not a boolean and `false or nil` raises.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.{Cases, Links, Works}
  alias Marginalia.Analysis.Linker

  setup %{conn: conn} do
    Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})
    # Restored, not deleted. `delete_env` drops the configured value instead
    # of putting it back, so anything reading `:owner_email` afterwards sees
    # nil rather than what config set — invisible in one run, because ExUnit
    # runs the async readers before these sync modules, and immediately fatal
    # under --repeat-until-failure, which is the tool for finding flakes.
    previous_owner = Application.get_env(:marginalia, :owner_email)
    Application.put_env(:marginalia, :owner_email, "owner@example.com")

    on_exit(fn ->
      case previous_owner do
        nil -> Application.delete_env(:marginalia, :owner_email)
        email -> Application.put_env(:marginalia, :owner_email, email)
      end
    end)

    owner = user_fixture(%{email: "owner@example.com"})

    mk = fn title, role ->
      body =
        "# #{title}\n\nA sentence long enough to be a section.\n\n" <>
          String.duplicate("word ", 200)

      {:ok, w} = Works.create_work(owner.id, %{"title" => title, "body" => body})
      {:ok, w} = Works.set_status(w, "read")
      {:ok, w} = Cases.place(w, "Some v. Case", role)
      s = hd(Works.list_sections(w.id))

      {:ok, n} =
        Works.insert_node(%{
          work_id: w.id,
          section_id: s.id,
          node_type: "beat",
          title: "a beat in the #{role}",
          quote: "A sentence long enough"
        })

      {w, n}
    end

    {op, op_n} = mk.("Some v. Case — Opinion", "opinion")
    {di, di_n} = mk.("Some v. Case — Dissent", "dissent")

    {:ok, link} = Links.get_or_create(op.id, di.id)
    {:ok, _} = Links.set_status(link, "linked", %{summary: "They disagree."})

    Links.store_edges(
      link,
      [
        %{
          "from" => op_n.id,
          "to" => di_n.id,
          "type" => "tension",
          "why" => "They part on consent."
        },
        %{
          "from" => di_n.id,
          "to" => op_n.id,
          "type" => "answers",
          "why" => "It replies about standing."
        }
      ],
      Linker.types()
    )

    %{conn: conn, owner: owner, op: op}
  end

  test "it renders at all, with no filters set", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/cases/some-v-case")

    assert html =~ "Some v. Case"
    assert html =~ "They part on consent."
    # the clear button only appears once something is filtered
    refute html =~ ">clear<"
  end

  test "searching narrows the connections", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/cases/some-v-case")

    html = render_change(view, "search", %{"q" => "consent"})
    assert html =~ "They part on consent."
    refute html =~ "It replies about standing."
    assert html =~ ">clear<"

    # and clearing brings them back
    html = render_click(view, "clear", %{})
    assert html =~ "It replies about standing."
  end

  test "slicing by relation, and toggling it off again", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/cases/some-v-case")

    html = render_click(view, "kind", %{"k" => "tension"})
    assert html =~ "They part on consent."
    refute html =~ "It replies about standing."

    html = render_click(view, "kind", %{"k" => "tension"})
    assert html =~ "It replies about standing."
  end

  test "a search matching nothing says so", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/cases/some-v-case")
    html = render_change(view, "search", %{"q" => "zzzzz"})

    assert html =~ "Nothing matches that"
  end

  test "the fast track into a referential read is on the page", %{conn: conn, op: op} do
    {:ok, _view, html} = live(conn, ~p"/cases/some-v-case")

    assert html =~ "or one against another"
    # the label is the document's own name, which here is "Opinion"
    assert html =~ "Opinion ↔ Dissent"
    # and it leads with the opinion
    assert html =~ "lead=#{op.slug}"
  end

  # Three advocates all labelled "Oral argument" is not a label.
  test "each document is named by what distinguishes it", %{conn: conn, owner: owner} do
    body = "# x\n\nA sentence long enough to be a section.\n\n" <> String.duplicate("word ", 200)

    for who <- ["Argument: Amit Agarwal", "Argument: Gen. D. John Sauer"] do
      {:ok, w} =
        Works.create_work(owner.id, %{"title" => "Some v. Case — #{who}", "body" => body})

      {:ok, w} = Works.set_status(w, "read")
      {:ok, _} = Cases.place(w, "Some v. Case", "argument")
    end

    {:ok, _view, html} = live(conn, ~p"/cases/some-v-case")

    assert html =~ "Argument: Amit Agarwal"
    assert html =~ "Argument: Gen. D. John Sauer"
    refute html =~ ">Oral argument<"
  end

  test "a visitor who is not the owner still sees it", %{} do
    {:ok, _view, html} = live(build_conn(), ~p"/cases/some-v-case")
    assert html =~ "Some v. Case"
  end

  test "the way in is in the nav for everyone, signed in or not", %{conn: conn} do
    # the collections are published on purpose; hiding the link behind a
    # login hid the only public thing on the site
    logged_out = get(build_conn(), ~p"/cases") |> html_response(200)
    assert logged_out =~ ~s(href="/cases")

    signed_in = conn |> log_in_user(user_fixture()) |> get(~p"/cases") |> html_response(200)
    assert signed_in =~ ~s(href="/cases")
  end
end
