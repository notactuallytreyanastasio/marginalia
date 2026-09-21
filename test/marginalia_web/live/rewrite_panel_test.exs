defmodule MarginaliaWeb.RewritePanelTest do
  @moduledoc """
  The rewrite panel actually rendering.

  It stopped doing so for every selection, because the panel was handed
  `@rewrite_span` from inside a function component that had no such assign.
  A `KeyError` in a LiveView render does not surface as an error — it drops
  the socket — so the symptom was "one paragraph does nothing" and
  "more than one crashes", which are the same bug wearing two faces.

  Nothing here reaches the model: the panel renders as soon as the event is
  handled, which is before any answer comes back, and that render is the
  thing that was broken.
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

    para = fn lead -> lead <> " " <> String.duplicate("word ", 120) end

    body =
      "# A draft\n\n" <>
        para.("She had been standing at the window for an hour.") <>
        "\n\n" <>
        para.("The kettle went cold on the counter.") <>
        "\n\n" <> para.("Nobody moved to fill it again.")

    {:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})
    {:ok, work} = Works.set_status(work, "read")

    %{conn: log_in_user(conn, user), work: work}
  end

  defp first_ref(view) do
    [_, ref] = Regex.run(~r/id="block-([^"]+)"/, render(view))
    ref
  end

  defp open(view, text) do
    ref = first_ref(view)
    render_click(view, "suggest_rewrite", %{"text" => text, "ref" => ref})
    render(view)
  end

  test "one paragraph opens the panel instead of dropping the socket", %{conn: conn, work: work} do
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")

    html = open(view, String.duplicate("word ", 120))

    assert html =~ "mg-rewrite", "the panel has to be on the page at all"
    assert html =~ "Rewrites of"
  end

  test "several paragraphs open it too, and it says how much", %{conn: conn, work: work} do
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")

    span =
      Enum.map_join(1..4, "\n\n", fn i -> "Paragraph #{i}. " <> String.duplicate("word ", 150) end)

    html = open(view, span)

    assert html =~ "mg-rewrite"

    refute html =~ "Rewrites of one line",
           "four paragraphs is not one line, and saying so was the original report"

    assert html =~ ~r/Rewrites of \d{3,} words/
  end

  test "a long span shows its extent, since the rest runs off below the panel", %{
    conn: conn,
    work: work
  } do
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")

    span = "THE VERY START. " <> String.duplicate("middle ", 300) <> "THE VERY END."
    html = open(view, span)

    assert html =~ "THE VERY START"
    assert html =~ "THE VERY END"
    assert html =~ "mg-rw-extent"
  end

  test "the steer box is there and survives the panel opening", %{conn: conn, work: work} do
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")

    html = open(view, String.duplicate("word ", 120))

    assert html =~ "steer_rewrite"
    assert html =~ "ask for something specific"
  end

  test "the socket is still alive after all of it", %{conn: conn, work: work} do
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")

    open(view, String.duplicate("word ", 400))

    # a dropped socket makes this raise rather than return markup
    assert render(view) =~ "mg-read-body"
  end

  describe "the steering box" do
    test "is a textarea that can grow, not a one-line slot", %{conn: conn, work: work} do
      {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")
      html = open(view, String.duplicate("word ", 120))

      assert html =~ ~s(name="steer")
      assert html =~ "<textarea", "what people write here is a sentence or three"
      assert html =~ ~s(id="rw-steer")
    end

    test "is never disabled, because phx-update=ignore would freeze it that way", %{
      conn: conn,
      work: work
    } do
      {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")

      # the panel is opened while the pass is running, which is exactly when
      # `disabled={@working}` would be rendered true — and `ignore` means the
      # attribute never comes back off
      html = open(view, String.duplicate("word ", 120))

      [box] = Regex.run(~r/<textarea[^>]*id="rw-steer"[^>]*>/, html)

      refute box =~ "disabled",
             "it rendered disabled on first paint and stayed that way for good"

      assert box =~ ~s(phx-update="ignore"), "or half-typed text is lost on every patch"
    end

    test "the button is the thing that goes quiet during a pass", %{conn: conn, work: work} do
      {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")
      html = open(view, String.duplicate("word ", 120))

      assert html =~ ~r/<button[^>]*disabled[^>]*>\s*Again/
    end
  end
end
