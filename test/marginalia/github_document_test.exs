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

  defp file(path, status \\ "modified", added \\ 3, removed \\ 1),
    do: %{path: path, was: nil, status: status, added: added, removed: removed}

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

  describe "the files it touched" do
    test "paths and line counts, between the argument and the commits" do
      doc =
        GitHub.document(
          pr(%{
            files: [file("lib/a.ex"), file("lib/b.ex", "added", 96, 0)],
            changed_files: 2,
            commits: [commit("narrow the guard")]
          })
        )

      assert doc =~ "## Files changed (2)"
      assert doc =~ "- `lib/a.ex` +3 −1"
      assert doc =~ "- `lib/b.ex` +96 — new"

      order = fn needle -> :binary.match(doc, needle) |> elem(0) end

      assert order.("The guard was too wide") < order.("## Files changed"),
             "the argument still comes first"

      assert order.("## Files changed") < order.("## Commits"),
             "the paths are an index; the commits are the story"
    end

    test "no diff hunks, however the response arrived" do
      doc = GitHub.document(pr(%{files: [file("lib/a.ex")], changed_files: 1}))

      refute doc =~ "@@"
      refute doc =~ "+++"
      refute doc =~ "patch"
    end

    test "a rename reads as one, not as two files" do
      renamed = %{
        path: "test/cases_test.exs",
        was: "test/case_test.exs",
        status: "renamed",
        added: 2,
        removed: 2
      }

      doc = GitHub.document(pr(%{files: [renamed], changed_files: 1}))

      assert doc =~ "- `test/case_test.exs` → `test/cases_test.exs` +2 −2"
    end

    test "a file with no line changes says nothing about lines" do
      doc = GitHub.document(pr(%{files: [file(".formatter.exs", "modified", 0, 0)]}))

      assert doc =~ "- `.formatter.exs`\n" or String.ends_with?(doc, "- `.formatter.exs`")
      refute doc =~ "+0"
    end

    test "a deleted file is not reported as three added lines" do
      doc = GitHub.document(pr(%{files: [file("lib/gone.ex", "removed", 0, 40)]}))

      assert doc =~ "- `lib/gone.ex` −40 — deleted"
    end

    test "the header counts what the pull request touched, not what fitted" do
      many = for i <- 1..80, do: file("lib/f#{i}.ex")

      doc = GitHub.document(pr(%{files: many, changed_files: 326}))

      assert doc =~ "## Files changed (326, the first 60 listed)"
      assert doc =~ "`lib/f60.ex`"
      refute doc =~ "`lib/f61.ex`"
    end

    test "a pull request with no file list is a document without the section" do
      doc = GitHub.document(pr(%{commits: [commit("x")]}))

      refute doc =~ "Files changed"
    end

    test "a fetch that failed says so rather than looking like no files" do
      doc = GitHub.document(pr(%{files: {:error, :forbidden}}))

      assert doc =~ "## Files changed"
      assert doc =~ "could not be fetched"
      assert doc =~ "forbidden"
    end
  end
end
