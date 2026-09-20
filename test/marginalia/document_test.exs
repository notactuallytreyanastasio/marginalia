defmodule Marginalia.DocumentTest do
  @moduledoc """
  The whole document, read two ways.

  What is tested here is the checking and the staleness, not the prose: a
  citation to a section that does not exist reads exactly like one that is
  true, and is the failure a reader cannot catch without going and looking.
  """
  use Marginalia.DataCase, async: true

  import Marginalia.AccountsFixtures

  alias Marginalia.{Document, Summary, Works}

  setup do
    user = user_fixture()

    body =
      Enum.map_join(1..3, "\n\n", fn i ->
        "# Part #{i}\n\nSection #{i} body. " <> String.duplicate("word ", 300)
      end)

    {:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})
    %{work: work, sections: Works.list_sections(work.id)}
  end

  defp summarise_all(sections) do
    Enum.map(sections, fn s ->
      {:ok, s} =
        s
        |> Ecto.Changeset.change(
          summary: "What section #{s.ordinal} does.",
          summary_fingerprint: Summary.fingerprint(s),
          summary_body: s.body
        )
        |> Repo.update()

      s
    end)
  end

  describe "validate/3" do
    test "a citation to a real section is kept", %{sections: sections} do
      comp = %{
        "summary" => "It does a thing.",
        "throughline" => "One thread.",
        "movements" => [%{"heading" => "H", "sections" => [1, 2], "does" => "D"}]
      }

      {attrs, dropped} = Document.validate(comp, %{}, sections)

      assert [%{"sections" => [1, 2]}] = attrs.movements
      assert dropped == []
    end

    test "a citation to a section that does not exist is dropped and named", %{
      sections: sections
    } do
      comp = %{
        "summary" => "s",
        "throughline" => "t",
        "movements" => [%{"heading" => "H", "sections" => [1, 14], "does" => "D"}]
      }

      {attrs, dropped} = Document.validate(comp, %{}, sections)

      assert [%{"sections" => [1]}] = attrs.movements
      assert [reason] = dropped
      assert reason =~ "14"
      assert reason =~ "not sections here"
    end

    test "guidelines and tensions are checked the same way", %{sections: sections} do
      guide = %{
        "guidelines" => [%{"guideline" => "G", "because" => "B", "sections" => [2, 99]}],
        "tensions" => [%{"tension" => "T", "sections" => [40]}]
      }

      {attrs, dropped} = Document.validate(%{}, guide, sections)

      assert [%{"sections" => [2]}] = attrs.guidelines
      assert [%{"sections" => []}] = attrs.tensions
      assert length(dropped) == 2
    end

    test "no tensions is a real answer and not an error", %{sections: sections} do
      {attrs, dropped} =
        Document.validate(%{}, %{"guidelines" => [], "tensions" => []}, sections)

      assert attrs.tensions == []
      assert dropped == []
    end
  end

  describe "staleness" do
    test "a document with no summary is not current", %{work: work} do
      refute Document.current?(work)
      assert Document.get(work.id) == nil
    end

    test "the fingerprint is over the section summaries", %{sections: sections} do
      summarised = summarise_all(sections)
      a = Document.fingerprint(summarised)

      assert a == Document.fingerprint(summarised)

      # re-summarised: same text, different words for it
      reworded = List.update_at(summarised, 0, &%{&1 | summary: "Different words."})
      refute a == Document.fingerprint(reworded)

      # edited: same summary, different text under it
      edited = List.update_at(summarised, 0, &%{&1 | body: &1.body <> " and more."})
      refute a == Document.fingerprint(edited)
    end

    test "editing a section makes the document summary stale", %{work: work, sections: sections} do
      summarised = summarise_all(sections)

      {:ok, _} =
        %Marginalia.Works.DocumentSummary{}
        |> Marginalia.Works.DocumentSummary.changeset(%{
          work_id: work.id,
          summary: "The whole thing.",
          fingerprint: Document.fingerprint(summarised)
        })
        |> Repo.insert()

      assert Document.current?(work)

      first = hd(summarised)

      block =
        first.body |> String.split(~r/\n{2,}/, trim: true) |> Enum.find(&(&1 =~ "Section 1"))

      {:ok, _} = Works.replace_block(first, block, String.replace(block, "Section 1", "AMENDED"))

      refute Document.current?(Repo.reload!(work)),
             "a document summary built on a section that has since changed is out of date"
    end
  end

  test "a work with no sections is refused before any call", %{work: work} do
    Repo.delete_all(from s in Marginalia.Works.Section, where: s.work_id == ^work.id)
    assert Document.run(Repo.reload!(work)) == {:error, :no_sections}
  end
end
