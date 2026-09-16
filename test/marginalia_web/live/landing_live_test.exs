defmodule MarginaliaWeb.LandingLiveTest do
  use MarginaliaWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  test "renders the pitch and the promise", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Someone who has actually read the whole thing"
    assert html =~ "what a reader leaves in the margin"
    assert html =~ "It reads. You decide."
  end

  test "the page describes the surfaces the product actually has", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    # one section per surface — a feature nobody can picture is one nobody
    # asks for, and each of these shipped after the first version of this page
    assert html =~ "The page, with its notes in the margin"
    assert html =~ "A thread on one paragraph"
    assert html =~ "What leads to what"
    assert html =~ "The one place it writes"
    assert html =~ "Then you change it yourself"

    # and the affordances inside them
    assert html =~ "a hairline appears in the"
    assert html =~ "drawn to scale"
    assert html =~ "Connections"
    assert html =~ "Tensions"
  end

  test "it does not promise it will never write, now that it sometimes does", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    # Marginalia.Rewrite proposes prose, so the old blanket promise was a lie
    # the moment it shipped. The claim has to be the narrow, true one.
    refute html =~ "It never writes a word of your book"
    assert html =~ "This is the only"
    assert html =~ "It never applies anything"
    assert html =~ "No prose you did not ask for"
  end

  test "the privacy claim matches how drafts are actually protected", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    # uploading needs no account and a draft is secret by link, not by
    # account — the page used to say nobody else could see your work
    assert html =~ "No account to upload"
    assert html =~ "private to whoever holds its link"
    refute html =~ "nobody else here can see your work"
  end

  test "is a single document, not a layout nested inside itself", %{conn: conn} do
    conn = get(conn, ~p"/")
    body = html_response(conn, 200)

    # the bare layout is a ROOT layout; naming it as the live layout too would
    # render the whole page twice
    assert length(String.split(body, "<!DOCTYPE html>")) - 1 == 1
  end

  test "does not carry the scaffold auth menu, which would duplicate its own header", %{
    conn: conn
  } do
    body = conn |> get(~p"/") |> html_response(200)

    assert body =~ "MARGINALIA" or body =~ "Marginalia"
    refute body =~ ~s(menu menu-horizontal)
  end

  test "the margin carries the product's own notes on the pitch, including ones that argue with it" do
    {:ok, _view, html} = live(build_conn(), ~p"/")

    # the page is the demo: notes annotate the pitch rather than restating it
    assert html =~ "annotating its own pitch"
    # and at least one of them pushes back on the copy
    assert html =~ "they read as a contradiction"
    assert html =~ "This section argues with the one before it"
  end

  test "a logged-out visitor's CTAs go straight at the upload — no account needed" do
    {:ok, _view, html} = live(build_conn(), ~p"/")
    assert html =~ ~s(href="/works/new")
  end

  test "a logged-in writer's CTAs go to the upload page, not back to registration", %{conn: conn} do
    # registration bounces a logged-in user home, so pointing the CTA there
    # makes every button on the page a no-op — the bug this guards
    conn = log_in_user(conn, user_fixture())
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ ~s(href="/works/new")
    refute html =~ ~s(href="/users/register")
  end

  test "the margin offers sign-up actions, not just commentary" do
    {:ok, _view, html} = live(build_conn(), ~p"/")

    assert html =~ "Find yours"
    assert html =~ "Try to break it"
    # every action lands on the upload, which no longer needs an account
    assert html =~ ~s(href="/works/new")
  end

  test "worked examples are present and play in sequence" do
    {:ok, _view, html} = live(build_conn(), ~p"/")

    assert html =~ "Which thread did I set up and never pay off?"
    assert html =~ "Rewrite my opening paragraph so it hits harder."
    # the turns are staggered by index, which is what makes them play out
    assert html =~ ~s(style="--i:0")
    assert html =~ ~s(style="--i:2")
  end

  test "everything that animates is marked for the scroll observer" do
    {:ok, _view, html} = live(build_conn(), ~p"/")

    # if a note were not observed it would stay invisible forever
    assert html =~ "data-reveal"
    reveals = length(String.split(html, "data-reveal")) - 1
    assert reveals >= 10, "expected the rail to be revealed progressively, got #{reveals}"
  end

  test "just the notes drops the prose and keeps the rail", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html = render_click(view, "toggle_notes")

    assert html =~ "notes-only"
    # the notes survive the switch — they are the whole point of the mode
    assert html =~ "annotating its own pitch"
  end

  test "a logged-in writer is pointed at their drafts instead of log in", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Your drafts"
  end
end
