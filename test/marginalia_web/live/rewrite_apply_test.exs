defmodule MarginaliaWeb.RewriteApplyTest do
  @moduledoc """
  Dropping a candidate into the draft, and refusing to when it does not fit.

  The reported version: three paragraphs highlighted, the panel anchored to a
  fourth, and "start from this" replaced that fourth paragraph wholesale with
  a rewrite of the other three. `seeded/3` fell through to the candidate when
  the block did not contain the span, which is a silent substitution of the
  wrong text into the wrong place.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.Works

  setup %{conn: conn} do
    previous = Application.get_env(:marginalia, :deepseek_api_key)
    Application.put_env(:marginalia, :deepseek_api_key, "test-key")
    on_exit(fn -> Application.put_env(:marginalia, :deepseek_api_key, previous) end)

    user = user_fixture()

    body =
      "# A draft\n\n" <>
        "ALPHA the first paragraph. " <>
        String.duplicate("word ", 120) <>
        "\n\nBRAVO the second paragraph. " <>
        String.duplicate("word ", 120) <>
        "\n\nCHARLIE the third paragraph. " <> String.duplicate("word ", 120)

    {:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})
    {:ok, work} = Works.set_status(work, "read")

    %{conn: log_in_user(conn, user), work: work, user: user}
  end

  defp refs(view) do
    Regex.scan(~r/id="block-([^"]+)"/, render(view)) |> Enum.map(fn [_, r] -> r end)
  end

  # The refusal itself is unit-tested on Rewrite.place/3: reaching it through
  # the page needs a rewrite in assigns, which needs the model to answer.

  test "editing a paragraph with no rewrite open still works", %{conn: conn, work: work} do
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")
    [first | _] = refs(view)

    html = render_click(view, "edit_block", %{"ref" => first})

    assert html =~ "mg-edit"
    assert html =~ "ALPHA the first paragraph."
  end
end
