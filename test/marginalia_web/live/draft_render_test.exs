defmodule MarginaliaWeb.DraftRenderTest do
  @moduledoc """
  What a reader sees of a draft stored one sentence per line: paragraphs,
  and nothing between the sentences of one.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.Works

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})
    owner = user_fixture(%{email: Application.get_env(:marginalia, :owner_email)})

    body =
      "# The post\n\nAt 04:47 UTC agent-7 implemented the Guideline step\nreset for lock delay. " <>
        "The idea came from agent-8.\n\n> agent-8 logged that the cap locks a piece. Agent-7\n> read it.\n\n" <>
        "```\nline one\nline two\n```\n\n- one. Two.\n- three.\n\nEvery node, by minute. " <>
        String.duplicate("word ", 200)

    {:ok, work} = Works.create_work(owner.id, %{"title" => "The post", "body" => body})
    %{work: work}
  end

  test "sentences of a paragraph run on; the draft's blank lines are the only breaks", %{
    work: work
  } do
    {:ok, _view, html} = live(build_conn(), ~p"/drafts/#{work.slug}")

    refute html =~ "<br"

    assert html =~
             "<p>At 04:47 UTC agent-7 implemented the Guideline step reset for lock delay.\nThe idea came from agent-8.</p>"
  end

  test "a blockquote renders as one quoted paragraph", %{work: work} do
    {:ok, _view, html} = live(build_conn(), ~p"/drafts/#{work.slug}")
    [quote] = Regex.run(~r/<blockquote>.*?<\/blockquote>/s, html)
    assert quote =~ "<p>agent-8 logged that the cap locks a piece.\nAgent-7 read it.</p>"
    refute quote =~ "<br"
  end

  test "code keeps its line breaks and a list keeps its items", %{work: work} do
    {:ok, _view, html} = live(build_conn(), ~p"/drafts/#{work.slug}")
    assert html =~ "<code>line one\nline two\n</code>"
    assert html =~ "<li>one. Two.</li>"
    assert html =~ "<li>three.</li>"
  end

  test "the changes page shows the sentence that changed, on its own", %{work: work} do
    [s] = Works.list_sections(work.id)
    para = s.body |> String.split("\n\n") |> Enum.find(&String.contains?(&1, "from agent-8."))

    {:ok, _} =
      Works.replace_block(
        s,
        para,
        String.replace(para, "from agent-8.", "from agent-8's decision.")
      )

    {:ok, _view, html} = live(build_conn(), ~p"/drafts/#{work.slug}/changes")
    assert html =~ "1 edited"
    [row] = Regex.run(~r/<div class="mg-diff-row change">.*?<\/div>\s*<\/div>/s, html)
    assert row =~ ~s(class="w ins")
    assert row =~ "decision."
    assert row =~ ~s(class="w del")
  end
end
