defmodule Marginalia.GitTest do
  @moduledoc """
  A draft's history as a real repository.

  The tests run `git` for the same reason the module does: a reimplementation
  that agrees with itself proves nothing, and the point of this is that the
  writer can clone the result.
  """
  use Marginalia.DataCase, async: false

  import Marginalia.AccountsFixtures

  alias Marginalia.{Git, Works}

  setup do
    root = Path.join(System.tmp_dir!(), "mg-git-#{System.unique_integer([:positive])}")
    previous = Application.get_env(:marginalia, :draft_repo_root)
    Application.put_env(:marginalia, :draft_repo_root, root)

    on_exit(fn ->
      Application.put_env(:marginalia, :draft_repo_root, previous)
      File.rm_rf(root)
    end)

    user = user_fixture()

    body =
      "# A draft\n\nALPHA the first paragraph. " <>
        String.duplicate("word ", 120) <>
        "\n\nBRAVO the second paragraph. " <> String.duplicate("word ", 120)

    {:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})
    %{work: work, user: user, root: root}
  end

  defp git(work, args), do: System.cmd("git", args, cd: Git.path(work), stderr_to_stdout: true)

  test "the first commit creates a real repository", %{work: work} do
    assert {:ok, sha} = Git.commit(work, "First")
    assert sha =~ ~r/^[0-9a-f]{4,}$/

    assert File.dir?(Path.join(Git.path(work), ".git"))
    assert {out, 0} = git(work, ["log", "--oneline"])
    assert out =~ "First"
  end

  test "the document is in the tree, with the draft identified", %{work: work} do
    {:ok, _} = Git.commit(work, "First")

    contents = File.read!(Path.join(Git.path(work), "draft.md"))

    assert contents =~ "ALPHA the first paragraph."
    assert contents =~ "slug: #{work.slug}"
    assert contents =~ "title: Draft"
  end

  test "committing an unchanged draft is not a commit", %{work: work} do
    {:ok, _} = Git.commit(work, "First")
    assert Git.commit(work, "Again") == {:ok, :unchanged}

    assert {out, 0} = git(work, ["log", "--oneline"])
    assert length(String.split(out, "\n", trim: true)) == 1
  end

  test "an edit becomes a second commit whose patch is the change", %{work: work} do
    {:ok, _} = Git.commit(work, "As it arrived")

    section = hd(Works.list_sections(work.id))

    block =
      section.body
      |> String.split(~r/\n{2,}/, trim: true)
      |> Enum.find(&String.contains?(&1, "ALPHA"))

    {:ok, _} = Works.replace_block(section, block, String.replace(block, "ALPHA", "AMENDED"))

    work = Works.get_by_slug(work.slug)
    assert {:ok, _sha} = Git.commit(work, "rewrite: cuts the gloss")

    assert {:ok, entries} = Git.log(work)
    assert [%{subject: "rewrite: cuts the gloss"}, %{subject: "As it arrived"}] = entries

    assert {:ok, patch} = Git.show(work, hd(entries).sha)
    assert patch =~ "-" <> "ALPHA" or patch =~ "ALPHA"
    assert patch =~ "AMENDED"
  end

  test "a multi-line message is reduced to a subject", %{work: work} do
    {:ok, _} = Git.commit(work, "line one\nline two\n\nline three")
    assert {:ok, [%{subject: subject}]} = Git.log(work)

    refute subject =~ "\n"
    assert subject == "line one line two line three"
  end

  test "a title with quotes in it does not break the commit", %{user: user} do
    {:ok, work} =
      Works.create_work(user.id, %{
        "title" => ~s(A "quoted" title; rm -rf /),
        "body" => "# H\n\n" <> String.duplicate("word ", 300)
      })

    assert {:ok, _} = Git.commit(work, "subject with \"quotes\" and $(echo hi)")
    assert {:ok, [%{subject: s}]} = Git.log(work)
    assert s =~ "quotes"
  end

  test "a bad sha is refused rather than passed to git", %{work: work} do
    {:ok, _} = Git.commit(work, "First")
    assert Git.show(work, "--not-a-sha") == {:error, :bad_sha}
    assert Git.show(work, "; rm -rf /") == {:error, :bad_sha}
  end

  test "a log for a draft with no repository says so", %{work: work} do
    assert Git.log(work) == {:error, :no_repo}
  end

  describe "when the deploy has not configured a root" do
    setup do
      previous = Application.get_env(:marginalia, :draft_repo_root)
      Application.delete_env(:marginalia, :draft_repo_root)
      on_exit(fn -> Application.put_env(:marginalia, :draft_repo_root, previous) end)
      :ok
    end

    test "nothing is written and it says why", %{work: work} do
      refute Git.enabled?()
      assert Git.commit(work, "First") == {:error, :not_configured}
      assert Git.log(work) == {:error, :not_configured}
      assert Git.path(work) == nil
    end
  end
end
