defmodule Marginalia.SelectionTest do
  @moduledoc """
  A selection is made against rendered text; the draft is markdown.

  Three earlier attempts encoded the ways those differ — strip backticks,
  blank out link targets, blank out list markers — and each fixed one
  construct while leaving every other one broken. This aligns the page back
  to the source instead, so there is no markdown knowledge to be incomplete.
  Every case below is a construct nobody had to write a rule for.
  """
  use Marginalia.DataCase, async: true

  alias Marginalia.{Selection, Works}
  import Marginalia.AccountsFixtures

  # select the middle of a block the way a person drags across it
  defp select(source) do
    source
    |> Selection.rendered_text()
    |> Selection.squash()
    |> String.split(" ", trim: true)
    |> then(fn w -> w |> Enum.slice(1, max(length(w) - 2, 2)) |> Enum.join(" ") end)
  end

  defp roundtrip(source) do
    sel = select(source)
    span = Selection.in_block(source, sel)

    assert span, "nothing matched for #{inspect(sel)}"
    assert String.contains?(source, span), "the span must be a literal substring of the draft"

    # and it must actually cover what was selected
    for word <- sel |> String.split(" ") |> Enum.take(3) do
      assert String.contains?(span, word), "span #{inspect(span)} is missing #{inspect(word)}"
    end

    span
  end

  describe "constructs nobody wrote a rule for" do
    test "links", do: roundtrip("Ten years ago, [I wrote a runner](https://x.test/p) after Jose said so.")
    test "code spans", do: roundtrip("We will use `gen_stage`, which happens *elsewhere* entirely.")
    test "numbered lists", do: roundtrip("1. The purpose of society is to make people better off\n2. In general it is hard")
    test "bullets", do: roundtrip("- a bullet item here\n- another bullet entirely")
    test "blockquotes", do: roundtrip("> a quoted line here for us to read")
    test "tables", do: roundtrip("| who | named |\n|---|---|\n| Dario | yes |")
    test "headings", do: roundtrip("## Step 4: Creating the Producer")
    test "entities", do: roundtrip("Tom &amp; Jerry went to the shop today")
    test "nested emphasis", do: roundtrip("This is **bold with _nested_ emphasis** inside it")
    test "images", do: roundtrip("Look at ![a diagram](/img/x.png) closely now please")
    test "fenced code", do: roundtrip("```elixir\ndef handle(demand, state) do\n  {:noreply, [], state}\nend\n```")
  end

  describe "locate/2" do
    setup do
      user = user_fixture()

      body =
        "# A draft\n\nShe stood at the [window](https://x.test) for an hour.\n\n" <>
          "1. The purpose of society is to make those living in it better off\n" <>
          "2. In general, it is better to make the less well off better off\n\n" <>
          String.duplicate("word ", 300)

      {:ok, work} = Works.create_work(user.id, %{"title" => "W", "body" => body})
      %{work: work}
    end

    test "finds a selection and returns the source span", %{work: work} do
      assert {:ok, %{span: span, section: section}} =
               Selection.locate(work, "She stood at the window for an hour")

      assert String.contains?(work.body, span)
      assert span =~ "[window](https://x.test)"
      assert section.ordinal == 1
    end

    test "a selection dragged across a paragraph break still lands", %{work: work} do
      sel = "for an hour. The purpose of society is to make those living in it better off"
      assert {:ok, %{span: span}} = Selection.locate(work, sel)
      assert String.contains?(work.body, span)
    end

    test "something not in the draft is refused", %{work: work} do
      assert Selection.locate(work, "a sentence that appears nowhere at all") == :error
    end

    test "a stray click is refused", %{work: work} do
      assert Selection.locate(work, "the") == :error
    end
  end

  test "the strict matcher the beats rely on is untouched" do
    alias Marginalia.Analysis.Anchor
    src = "1. The purpose of society is to make people better off"

    # it matches literally, folding only whitespace and typography
    assert {:ok, "1. The purpose of society"} = Anchor.verify("1. The purpose of society", src)
    assert {:ok, _} = Anchor.verify("The  purpose\nof society", src)

    # and it still refuses a reordering, which is the guarantee the beats rest on
    assert Anchor.verify("society of purpose the", src) == :error
  end
end
