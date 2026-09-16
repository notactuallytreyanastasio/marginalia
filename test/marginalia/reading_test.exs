defmodule Marginalia.ReadingTest do
  @moduledoc """
  The page view. Notes sit beside the paragraph that caused them, which is
  only possible because every note carries a span verified against the source.
  """
  use Marginalia.DataCase, async: true

  alias Marginalia.{Reading, Works}
  import Marginalia.AccountsFixtures

  @body """
  # A draft

  She had been standing at the window for an hour before anyone noticed.

  The kettle went cold on the counter, and nobody moved to fill it again.

  By evening the argument had found its real subject, which was not the kettle.
  """

  setup do
    user = user_fixture()
    {:ok, work} = Works.create_work(user.id, %{"title" => "W", "body" => @body})
    %{work: work, section: hd(Works.list_sections(work.id))}
  end

  test "a note lands on the paragraph its quote came from", %{work: work, section: s} do
    {:ok, _} =
      Works.insert_node(%{
        work_id: work.id,
        section_id: s.id,
        node_type: "beat",
        title: "The kettle goes cold",
        quote: "The kettle went cold on the counter"
      })

    [page] = Reading.page(work)
    assert page.unplaced == []

    with_notes = Enum.filter(page.blocks, &(&1.notes != []))
    assert [block] = with_notes
    assert [%{title: "The kettle goes cold"}] = block.notes
    assert block.text =~ "kettle went cold"
    assert block.mark == "The kettle went cold on the counter"
    # every paragraph carries a stable id the rail can point a note at
    assert block.ref =~ ~r/^s\d+p\d+$/
  end

  test "a note whose quote is nowhere is kept, not silently dropped", %{work: work, section: s} do
    {:ok, _} =
      Works.insert_node(%{
        work_id: work.id,
        section_id: s.id,
        node_type: "beat",
        title: "Invented",
        quote: "a sentence that is not in this draft at all"
      })

    [page] = Reading.page(work)
    assert Enum.all?(page.blocks, &(&1.notes == []))
    assert [%{title: "Invented"}] = page.unplaced
  end

  describe "the draft's own markdown" do
    @code """
    Create a new file:

    ```elixir
    defmodule Producer do
      use GenStage

      def handle_demand(demand, state) do
        {:noreply, [], state}
      end
    end
    ```

    The consumer is in control. It's **impossible** to overwhelm it.

    1. First principle
    2. Second principle
    """

    # a fence contains blank lines, and splitting on those tore it in half:
    # the draft came out as reflowed serif with stray backticks in it
    test "a fenced code block survives the blank lines inside it" do
      blocks = Reading.split(@code)
      fence = Enum.find(blocks, &String.starts_with?(&1, "```"))

      assert fence, "the fence should be one block"
      assert fence =~ "handle_demand"
      assert fence =~ "end\n```"
    end

    test "a fence renders as code, not as prose" do
      fence = Reading.split(@code) |> Enum.find(&String.starts_with?(&1, "```"))
      html = fence |> Reading.render_block(nil, "x") |> html_of()

      assert html =~ "<pre><code"
      refute html =~ "`", "no backticks should reach the page"
    end

    test "a list renders as a list" do
      list = Reading.split(@code) |> Enum.find(&String.starts_with?(&1, "1."))
      assert Reading.render_block(list, nil, "y") |> html_of() =~ "<ol>"
    end

    test "a highlight survives rendering, even across inline markup" do
      para = Reading.split(@code) |> Enum.find(&String.contains?(&1, "impossible"))

      html =
        para
        |> Reading.render_block("It's **impossible** to overwhelm it", "z")
        |> html_of()

      assert html =~ ~s(<mark id="anchor-z">)
      # the bold inside the span is still bold, and the mark wraps it
      assert html =~ "<strong>impossible</strong>"
      assert html =~ "</mark>"
    end

    test "a block with no highlight gets no mark" do
      para = Reading.split(@code) |> Enum.find(&String.contains?(&1, "impossible"))
      refute Reading.render_block(para, nil, "z") |> html_of() =~ "<mark"
    end

    test "the sentinels never reach the page" do
      para = Reading.split(@code) |> Enum.find(&String.contains?(&1, "impossible"))
      html = Reading.render_block(para, "The consumer is in control", "z") |> html_of()

      refute html =~ "\u{E000}"
      refute html =~ "\u{E001}"
    end

    defp html_of({:safe, h}), do: IO.iodata_to_binary(h)
  end

  describe "trimming" do
    setup %{work: work, section: s} do
      [a, b] =
        Works.insert_nodes(work.id, s.id, [
          %{node_type: "beat", title: "The window", quote: "standing at the window for an hour"},
          %{node_type: "beat", title: "The kettle", quote: "The kettle went cold on the counter"}
        ])

      Works.link(work.id, a.id, b.id, "tension", 0, "the two do not sit together")
      %{a: a, b: b}
    end

    defp kinds(work, only) do
      work
      |> Reading.page(only: only)
      |> Enum.flat_map(& &1.blocks)
      |> Enum.flat_map(& &1.notes)
      |> Enum.map(& &1.kind)
      |> Enum.sort()
    end

    test "everything shows beats and connections", %{work: work} do
      assert kinds(work, nil) == ["beat", "beat", "tension"]
    end

    test "beats alone", %{work: work}, do: assert(kinds(work, "beats") == ["beat", "beat"])
    test "tensions alone", %{work: work}, do: assert(kinds(work, "tensions") == ["tension"])
  end

  describe "focus/2" do
    test "a beat carries its own section in full", %{work: work, section: s} do
      {:ok, n} =
        Works.insert_node(%{
          work_id: work.id,
          section_id: s.id,
          node_type: "beat",
          title: "The kettle",
          quote: "The kettle went cold on the counter"
        })

      focus = Reading.focus(work, "beat:#{n.id}")
      assert focus.kind == "beat"
      assert focus.title == "The kettle"
      assert [%{id: id}] = focus.sections
      assert id == s.id
    end

    test "a connection carries both ends' sections", %{work: work, section: s} do
      two =
        "# One\n\n" <>
          String.duplicate("early ", 300) <> "\n\n# Two\n\n" <> String.duplicate("later ", 300)

      {:ok, work2} = Works.create_work(work.user_id, %{"title" => "Two", "body" => two})
      [s1, s2] = Works.list_sections(work2.id) |> Enum.take(2)
      {:ok, a} = Works.insert_node(%{work_id: work2.id, section_id: s1.id, node_type: "beat", title: "A"})
      {:ok, b} = Works.insert_node(%{work_id: work2.id, section_id: s2.id, node_type: "beat", title: "B"})
      Works.link(work2.id, a.id, b.id, "pays_off", 0, "A promises what B delivers")

      focus = Reading.focus(work2, "conn:#{a.id}:#{b.id}:pays_off")
      assert focus.kind == "pays_off"
      assert focus.body == "A promises what B delivers"
      assert length(focus.sections) == 2
      assert Enum.map(focus.sections, & &1.ordinal) == [1, 2]
      assert s.id != s1.id
    end

    test "a nonsense key is nil rather than a crash", %{work: work} do
      assert Reading.focus(work, "beat:999999") == nil
      assert Reading.focus(work, "garbage") == nil
    end
  end

  describe "a highlight that lands on markdown syntax" do
    test "emphasis around the quote still renders, and the mark sits inside it" do
      # a beat is anchored to a literal substring of the draft, and the draft
      # is markdown — so a quote of a bolded sentence carries its ** along.
      # Wrapping that in the mark sentinel used to break the delimiter pair
      # and print four asterisks at the reader.
      text = "Prudence. **We must slow the pace. Progress will still seem fast.** Two things."
      quote = "**We must slow the pace. Progress will still seem fast.**"

      {:safe, html} = Marginalia.Reading.render_block(text, quote, "r1")

      refute html =~ "**"
      assert html =~ "<strong>"
      assert html =~ ~s(<mark id="anchor-r1">We must slow the pace.)
    end

    test "italics and code fences at the edges are trimmed out of the mark too" do
      for {open, close, tag} <- [{"*", "*", "em"}, {"`", "`", "code"}] do
        text = "Before #{open}the marked words#{close} after."
        {:safe, html} = Marginalia.Reading.render_block(text, "#{open}the marked words#{close}", "r2")

        assert html =~ "<#{tag}>"
        assert html =~ "<mark"
        refute html =~ "#{open}the marked"
      end
    end

    test "a quote that is only delimiters marks nothing rather than crashing" do
      text = "Some prose with ** in it somewhere."
      {:safe, html} = Marginalia.Reading.render_block(text, "**", "r3")
      assert is_binary(html)
    end

    test "an ordinary quote is untouched" do
      text = "She had been standing at the window for an hour."
      {:safe, html} = Marginalia.Reading.render_block(text, "standing at the window", "r4")
      assert html =~ ~s(<mark id="anchor-r4">standing at the window</mark>)
    end
  end
end
