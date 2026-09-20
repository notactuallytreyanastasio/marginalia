defmodule Marginalia.SummaryTest do
  @moduledoc """
  A summary of a section, and knowing when it has stopped being true.

  A summary of prose that has since been rewritten is worse than none: it is
  a confident description of text that is not there.
  """
  use Marginalia.DataCase, async: true

  import Marginalia.AccountsFixtures

  alias Marginalia.{Repo, Summary, Works}

  setup do
    user = user_fixture()

    body =
      "# One\n\nALPHA the first paragraph. " <>
        String.duplicate("word ", 300) <> "\n\n# Two\n\nBRAVO. " <> String.duplicate("word ", 300)

    {:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})
    %{work: work, section: hd(Works.list_sections(work.id))}
  end

  test "a section with no summary is not current", %{section: section} do
    refute Summary.current?(section)
  end

  test "a stored summary is current against the text it was made from", %{section: section} do
    {:ok, section} =
      section
      |> Ecto.Changeset.change(
        summary: "It sets up alpha.",
        summary_fingerprint: Summary.fingerprint(section)
      )
      |> Repo.update()

    assert Summary.current?(section)
  end

  test "editing the section makes its summary stale", %{work: work, section: section} do
    {:ok, section} =
      section
      |> Ecto.Changeset.change(
        summary: "It sets up alpha.",
        summary_fingerprint: Summary.fingerprint(section)
      )
      |> Repo.update()

    assert Summary.current?(section)

    block =
      section.body
      |> String.split(~r/\n{2,}/, trim: true)
      |> Enum.find(&String.contains?(&1, "ALPHA"))

    {:ok, _} = Works.replace_block(section, block, String.replace(block, "ALPHA", "AMENDED"))

    refute Summary.current?(Repo.reload!(section)),
           "a summary of prose that has been rewritten describes text that is not there"

    assert Repo.reload!(section).summary == "It sets up alpha.",
           "the stale summary is kept and marked, not silently deleted"

    assert work.id
  end

  test "an empty section is refused before any call is made", %{section: section} do
    assert Summary.run(%{section | body: "   "}) == {:error, :empty}
  end

  test "the fingerprint changes with the text and not with anything else", %{section: section} do
    a = Summary.fingerprint(section)
    assert a == Summary.fingerprint(%{section | title: "A different title"})
    refute a == Summary.fingerprint(%{section | body: section.body <> " more"})
  end
end
