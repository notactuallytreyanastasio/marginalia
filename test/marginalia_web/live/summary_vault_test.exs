defmodule MarginaliaWeb.SummaryVaultTest do
  @moduledoc """
  What the browser needs in order to keep a summary the server will overwrite.

  `Summary.store/3` writes one row per section, so running it again destroys
  the text that was there. The vault is a per-browser safety net for exactly
  that, and what can be tested here is that the page hands it everything it
  needs: a stable key, the text, and when it was written.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.{Summary, Works}

  setup %{conn: conn} do
    Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})
    user = user_fixture()

    body =
      "# One\n\n" <>
        String.duplicate("word ", 300) <> "\n\n# Two\n\n" <> String.duplicate("word ", 300)

    {:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})
    {:ok, work} = Works.set_status(work, "read")

    %{conn: log_in_user(conn, user), work: work, user: user}
  end

  defp summarise(work, text) do
    section = hd(Works.list_sections(work.id))

    {:ok, s} =
      section
      |> Ecto.Changeset.change(
        summary: text,
        summary_fingerprint: Summary.fingerprint(section),
        summary_body: section.body,
        summarised_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )
      |> Marginalia.Repo.update()

    s
  end

  test "a summary carries a key, its text and its time", %{conn: conn, work: work} do
    summarise(work, "It establishes the doorway.")
    {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}?view=read")

    assert html =~ ~s(data-sum-key="#{work.slug}:1"),
           "the key has to name the draft and the section, or two drafts share a vault"

    assert html =~ "It establishes the doorway."
    assert html =~ "data-sum-at="
  end

  test "the container the hook writes into is left alone by LiveView", %{conn: conn, work: work} do
    summarise(work, "A summary.")
    {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}?view=read")

    assert html =~ ~s(id="sumvault-1")

    vault = Regex.run(~r/<div[^>]*id="sumvault-1"[^>]*>/, html) |> hd()

    assert vault =~ ~s(phx-update="ignore"),
           "without this a re-render wipes what the hook put there"
  end

  test "a section with no summary offers no vault", %{conn: conn, work: work} do
    {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}?view=read")

    refute html =~ "data-sum-key="
    refute html =~ ~s(id="sumvault-)
  end

  test "the hook is attached to something", %{conn: conn, work: work} do
    summarise(work, "A summary.")
    {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}?view=read")

    assert html =~ ~s(phx-hook="MarginaliaWeb.WorkLive.Show.SummaryVault"),
           "a colocated hook that is never attached does nothing at all"
  end

  test "the key survives a re-summarise, so both versions land in one vault", %{
    conn: conn,
    work: work
  } do
    summarise(work, "The first summary.")
    {:ok, _view, first} = live(conn, ~p"/works/#{work.slug}?view=read")

    summarise(work, "A completely different second summary.")
    {:ok, _view, second} = live(conn, ~p"/works/#{work.slug}?view=read")

    key = ~s(data-sum-key="#{work.slug}:1")
    assert first =~ key and second =~ key

    assert second =~ "A completely different second summary."

    refute second =~ "The first summary.",
           "the server has genuinely lost it, which is why the browser keeps it"
  end
end
