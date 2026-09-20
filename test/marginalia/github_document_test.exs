defmodule Marginalia.GitHubDocumentTest do
  @moduledoc """
  What one pull request becomes when it is read as a chapter.

  The writeup is the author's argument about their own work. The commits are
  what they actually did, and the sentence that turns out to matter — why the
  obvious version was wrong — is usually in a commit message and nowhere
  else. A stack read from descriptions alone cannot see it.
  """
  use ExUnit.Case, async: true

  alias Marginalia.Import.GitHub

  defp pr(attrs) do
    Map.merge(
      %{
        ordinal: 1,
        number: 7,
        title: "7. A guard that took too much",
        body: "The guard was too wide, so three responses came back with no body.",
        url: "https://github.com/o/r/pull/7",
        commits: []
      },
      attrs
    )
  end

  defp commit(subject, detail \\ "") do
    %{sha: "abc12345", message: if(detail == "", do: subject, else: "#{subject}\n\n#{detail}")}
  end

  test "the writeup comes first and the commits follow it" do
    doc = GitHub.document(pr(%{commits: [commit("be-blimp: narrow the guard")]}))

    assert doc =~ "The guard was too wide"
    assert doc =~ "## Commits (1)"
    assert doc =~ "be-blimp: narrow the guard"

    writeup_at = :binary.match(doc, "The guard was too wide") |> elem(0)
    commits_at = :binary.match(doc, "## Commits") |> elem(0)

    assert writeup_at < commits_at,
           "the argument has to survive the window Stacks.text_of/1 reads"
  end

  test "a commit message keeps its body, which is where the reasoning lives" do
    why = "The obvious version drops the last frame, because the reader is closed first."
    doc = GitHub.document(pr(%{commits: [commit("be-blimp: close the reader last", why)]}))

    assert doc =~ why
  end

  test "the short sha rides along, so a claim can be chased" do
    doc = GitHub.document(pr(%{commits: [commit("be-blimp: narrow the guard")]}))
    assert doc =~ "(abc12345)"
  end

  test "a pull request with no description still carries its commits" do
    doc = GitHub.document(pr(%{body: "", commits: [commit("be-blimp: narrow the guard")]}))

    assert doc =~ "has no description"
    assert doc =~ "be-blimp: narrow the guard"
  end

  test "no commits adds no section at all" do
    doc = GitHub.document(pr(%{commits: []}))

    refute doc =~ "## Commits"
    assert doc =~ "The guard was too wide"
  end

  test "a failed commit fetch says so in the document rather than looking empty" do
    doc = GitHub.document(pr(%{commits: {:error, {:http, 502}}}))

    assert doc =~ "could not be fetched"
    assert doc =~ "502"

    refute doc =~ "## Commits (0)",
           "a chapter whose trail failed must not read as a chapter that had none"
  end

  test "a very long trail is cut, and says it was cut" do
    many = for i <- 1..400, do: commit("commit #{i}", String.duplicate("detail ", 40))
    doc = GitHub.document(pr(%{commits: many}))

    assert doc =~ "commit trail truncated"
    assert doc =~ "## Commits (400)", "the real count survives the cut"

    assert String.length(doc) < 14_000,
           "the whole document has to fit the window Stacks.text_of/1 reads"
  end

  test "the writeup is never what gets cut" do
    argument = "This is the load-bearing sentence of the chapter."
    many = for i <- 1..400, do: commit("commit #{i}", String.duplicate("detail ", 40))
    doc = GitHub.document(pr(%{body: argument, commits: many}))

    assert doc =~ argument
  end
end
