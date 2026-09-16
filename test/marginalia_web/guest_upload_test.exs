defmodule MarginaliaWeb.GuestUploadTest do
  @moduledoc """
  Uploading no longer needs an account. The property that must survive that:
  a guest can reach their own drafts and nobody else's.
  """
  use MarginaliaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.{Accounts, Works}

  describe "arriving with no account" do
    test "is let in, and given a guest of their own", %{conn: conn} do
      conn = get(conn, ~p"/works/new")
      assert html_response(conn, 200) =~ "Upload a draft"

      assert %{user: user} = conn.assigns.current_scope
      assert user.is_guest
      assert get_session(conn, :user_token)
    end

    test "the same session keeps the same guest", %{conn: conn} do
      conn = get(conn, ~p"/works/new")
      first = conn.assigns.current_scope.user.id

      conn = get(conn, ~p"/works")
      assert conn.assigns.current_scope.user.id == first
    end

    test "two different visitors get two different guests", %{conn: conn} do
      a = get(conn, ~p"/works/new").assigns.current_scope.user
      b = get(build_conn(), ~p"/works/new").assigns.current_scope.user

      assert a.id != b.id
      assert a.email != b.email
    end
  end

  describe "a draft is unlisted, and the link is the permission" do
    setup do
      {:ok, guest} = Accounts.create_guest_user()

      {:ok, work} =
        Works.create_work(guest.id, %{"title" => "Mine", "body" => String.duplicate("w ", 300)})

      %{guest: guest, work: work}
    end

    test "the url carries an unguessable slug, not the row id", %{work: work} do
      assert byte_size(work.slug) >= 20
      refute work.slug == to_string(work.id)
      assert Works.get_by_slug(work.slug).id == work.id
    end

    test "a guessed slug gets nothing", %{conn: conn} do
      conn = get(conn, ~p"/works")
      assert {:error, {:live_redirect, %{to: "/works"}}} = live(conn, ~p"/works/1")
      assert text_response(get(conn, ~p"/works/1/graph.json"), 404)
    end

    test "the owner sees it as theirs, with a link to hand out", %{conn: conn, guest: guest, work: work} do
      conn = log_in_user(conn, guest)
      {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}")

      assert html =~ "Mine"
      assert html =~ "Copy link"
      refute html =~ "reading someone&#39;s draft"
    end

    test "someone with the link can read it", %{conn: conn, work: work} do
      conn = get(conn, ~p"/works")
      {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}")

      assert html =~ "Mine"
      assert html =~ "reading someone&#39;s draft"
      refute html =~ "Copy link"
    end

    test "but cannot spend the owner's model credit or change the draft",
         %{conn: conn, work: work} do
      conn = get(conn, ~p"/works")
      {:ok, view, _html} = live(conn, ~p"/works/#{work.slug}")

      for event <- ~w(send build_graph start_read) do
        params = if event == "send", do: %{"message" => "hello"}, else: %{}
        assert render_click(view, event, params) =~ "You can read it, not change it"
      end

      # nothing was asked, nothing was started
      assert Marginalia.Chat.messages_sent(work.user_id) == 0
      assert Works.get_by_slug(work.slug).status == "pending"
    end

    test "it does not show up in anyone else's list", %{conn: conn} do
      conn = get(conn, ~p"/works")
      refute html_response(conn, 200) =~ "Mine"
    end
  end

  describe "settings still need a real account" do
    test "a guest is sent to sign up, not to log in — they have nothing to log in with",
         %{conn: conn} do
      {:ok, guest} = Accounts.create_guest_user()
      conn = conn |> log_in_user(guest) |> get(~p"/users/settings")
      assert redirected_to(conn) == ~p"/users/register"
    end

    test "a real account gets in", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/users/settings")
      assert html_response(conn, 200)
    end
  end

  describe "claiming the account keeps the work" do
    test "a guest becomes a real user and keeps everything they uploaded" do
      {:ok, guest} = Accounts.create_guest_user()
      {:ok, work} = Works.create_work(guest.id, %{"title" => "Kept", "body" => String.duplicate("w ", 300)})

      {:ok, claimed} =
        Accounts.claim_guest_account(guest, %{
          email: "real@example.com",
          password: "a-long-enough-password"
        })

      refute claimed.is_guest
      assert claimed.email == "real@example.com"
      assert claimed.id == guest.id
      # same row, so the work never moved
      assert [%{id: id}] = Works.list_works(claimed.id)
      assert id == work.id
      assert Accounts.get_user_by_email_and_password("real@example.com", "a-long-enough-password")
    end

    test "claiming a real account is refused" do
      user = user_fixture()
      assert {:error, _} = Accounts.claim_guest_account(user, %{email: "x@y.com", password: "whatever-long"})
    end
  end
end
