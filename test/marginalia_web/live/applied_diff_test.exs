defmodule MarginaliaWeb.AppliedDiffTest do
  @moduledoc """
  What a change looks like the moment it lands.

  Accepting a rewrite used to drop you back into plain prose: the dimming
  cleared, the panel closed, and nothing on the page said what had just
  happened to the paragraph you were looking at.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.Works

  setup %{conn: conn} do
    Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})
    user = user_fixture()

    body =
      "# One\n\nALPHA the first paragraph. " <>
        String.duplicate("word ", 150) <>
        "\n\nBRAVO the second paragraph. " <> String.duplicate("word ", 150)

    {:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})
    {:ok, work} = Works.set_status(work, "read")
    %{conn: log_in_user(conn, user), work: work}
  end

  defp first_ref(view) do
    [_, ref] = Regex.run(~r/id="block-([^"]+)"/, render(view))
    ref
  end

  test "an edit shows the before against the after, in place", %{conn: conn, work: work} do
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")
    ref = first_ref(view)

    render_click(view, "edit_block", %{"ref" => ref})
    html = render_submit(view, "save_block", %{"text" => "REPLACED ENTIRELY."})

    assert html =~ "REPLACED ENTIRELY."
    assert html =~ "mg-applied", "the paragraph shows what it replaced"
    assert html =~ "Before"
    assert html =~ "ALPHA", "the text that went has to still be visible"
  end

  test "it is dismissable, and then the paragraph is just a paragraph", %{conn: conn, work: work} do
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")
    ref = first_ref(view)

    render_click(view, "edit_block", %{"ref" => ref})
    render_submit(view, "save_block", %{"text" => "REPLACED ENTIRELY."})

    html = render_click(view, "dismiss_applied", %{})

    refute html =~ "mg-applied"
    assert html =~ "REPLACED ENTIRELY.", "the new text stays; only the comparison goes"
  end

  test "an untouched draft shows no comparison anywhere", %{conn: conn, work: work} do
    {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}?view=read")
    refute html =~ "mg-applied"
  end

  test "only the paragraph that changed shows one", %{conn: conn, work: work} do
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")
    ref = first_ref(view)

    render_click(view, "edit_block", %{"ref" => ref})
    html = render_submit(view, "save_block", %{"text" => "REPLACED ENTIRELY."})

    assert length(Regex.scan(~r/class="mg-applied"/, html)) == 1
    assert html =~ "BRAVO the second paragraph.", "the other paragraph is untouched prose"
  end
end
