defmodule Marginalia.Import.GitHub do
  @moduledoc """
  Importing a stack of pull requests as an ordered folder of drafts.

  A stack is pull requests each based on the one before it, so that the
  series reads in order and each diff shows only its own chapter. That shape
  is the whole reason it can be read as a method, and it is the thing this
  module checks rather than assumes.

  ## The order is derived, not fetched

  The order comes from walking `base` to `head` from the default branch, not
  from sorting on pull-request number. Those usually agree, and this refuses
  the import when they cannot both be true: two pull requests based on the
  default branch is two stacks, and a pull request whose base is not in the
  chain is not part of this one. A silently mis-ordered stack would produce
  a method whose steps are in the wrong order, which is worse than no import.

  ## The token

  Taken per request and never stored. It is the reader's own credential,
  the only thing it is used for is `GET`, and a token at rest in a database
  is a liability nobody asked this app to hold.

  Unlike `Marginalia.Import`, the host here is fixed, so there is no
  user-supplied URL to defend against — `owner` and `repo` are path
  segments, and they are the only part of the request a person controls.
  """

  require Logger

  alias Marginalia.{Folders, Repo, Works}

  @api "https://api.github.com"
  @timeout 20_000
  @per_page 100
  @max_pages 5

  @doc """
  Fetch the open pull requests of a repository as an ordered stack.

  Returns `{:ok, [%{ordinal:, title:, body:, url:, number:, commits:}]}`, or
  an error naming what is wrong with the stack rather than a bare failure.
  """
  def stack(owner, repo, token, opts \\ []) do
    with :ok <- check_name(owner),
         :ok <- check_name(repo),
         {:ok, default} <- default_branch(owner, repo, token),
         {:ok, pulls} <- pulls(owner, repo, token, opts[:state] || "open"),
         {:ok, items} <- order(pulls, default) do
      {:ok, Enum.map(items, &with_commits(&1, owner, repo, token))}
    end
  end

  # The writeup argues; the commits are what was actually done. A stack read
  # from descriptions alone is a stack read from the author's summary of
  # their own work, and the sentence that turns out to matter is usually the
  # one in a commit message explaining why the obvious version was wrong.
  #
  # A failure here does not lose the import. It is written into the document
  # instead, so a step read off a chapter with no commit trail says so rather
  # than looking like a chapter that had none.
  defp with_commits(item, owner, repo, token) do
    case get("/repos/#{owner}/#{repo}/pulls/#{item.number}/commits?per_page=#{@per_page}", token) do
      {:ok, commits} when is_list(commits) ->
        Map.put(item, :commits, Enum.map(commits, &to_commit/1))

      other ->
        Logger.warning("marginalia: commits for ##{item.number} failed: #{inspect(other)}")
        Map.put(item, :commits, {:error, other})
    end
  end

  # What a pull request touched, which is a different fact from what its
  # author says it did and cheaper to check than either the diff or the
  # commits. One request; the count comes off the pull request itself, so a
  # listing capped at a hundred can still say how many there really were.
  #
  # The response carries `patch` — the actual diff hunks — for every file,
  # and it is dropped here on purpose. A draft is something somebody reads
  # and argues with in the margin, and forty files of unified diff in it is
  # not that. The paths are the shape of the change; the hunks are the
  # change, and they belong in the repository.
  @file_cap 100

  defp with_files(item, owner, repo, token) do
    case get("/repos/#{owner}/#{repo}/pulls/#{item.number}/files?per_page=#{@file_cap}", token) do
      {:ok, files} when is_list(files) ->
        Map.put(item, :files, Enum.map(files, &to_file/1))

      other ->
        Logger.warning("marginalia: files for ##{item.number} failed: #{inspect(other)}")
        Map.put(item, :files, {:error, other})
    end
  end

  defp to_file(f) do
    %{
      path: f["filename"],
      was: f["previous_filename"],
      status: f["status"],
      added: f["additions"] || 0,
      removed: f["deletions"] || 0
    }
  end

  defp to_commit(c) do
    %{
      sha: String.slice(c["sha"] || "", 0, 8),
      message: String.trim(get_in(c, ["commit", "message"]) || "")
    }
  end

  # owner/repo go into a path, so they are checked rather than escaped: a
  # name that needs escaping is not a name.
  defp check_name(name) when is_binary(name) do
    if Regex.match?(~r/^[A-Za-z0-9._-]{1,100}$/, name), do: :ok, else: {:error, :bad_name}
  end

  defp check_name(_), do: {:error, :bad_name}

  defp default_branch(owner, repo, token) do
    case get("/repos/#{owner}/#{repo}", token) do
      {:ok, %{"default_branch" => b}} -> {:ok, b}
      {:ok, _} -> {:error, :no_default_branch}
      other -> other
    end
  end

  defp pulls(owner, repo, token, state) do
    Enum.reduce_while(1..@max_pages, {:ok, []}, fn page, {:ok, acc} ->
      case get(
             "/repos/#{owner}/#{repo}/pulls?state=#{state}&per_page=#{@per_page}&page=#{page}",
             token
           ) do
        {:ok, []} -> {:halt, {:ok, acc}}
        {:ok, batch} when length(batch) < @per_page -> {:halt, {:ok, acc ++ batch}}
        {:ok, batch} -> {:cont, {:ok, acc ++ batch}}
        other -> {:halt, other}
      end
    end)
  end

  defp get(path, token) do
    case Req.get(@api <> path,
           headers: [
             {"authorization", "Bearer #{token}"},
             {"accept", "application/vnd.github+json"},
             {"x-github-api-version", "2022-11-28"},
             {"user-agent", "marginalia"}
           ],
           receive_timeout: @timeout
         ) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: 401}} -> {:error, :unauthorized}
      {:ok, %{status: 403}} -> {:error, :forbidden}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, {:transport, inspect(reason)}}
    end
  end

  # --- the chain ------------------------------------------------------------

  # --- a pile, rather than a stack ------------------------------------------

  @doc """
  Every pull request of a repository, in no particular order.

  `stack/4` refuses anything that is not a strict base-to-head chain, which
  is right for importing a series and wrong for everything else: most
  repositories are not stacks, and "these forty pull requests are not a
  chain" is not a useful answer to "let me pick some of them".

  So this asks nothing of the shape. What comes back is one light row per
  pull request — enough to show a list and choose from it, and nothing
  more. The bodies and the commit trails are a request each and are only
  fetched for what somebody actually picks.
  """
  def list(owner, repo, token, opts \\ []) do
    with :ok <- check_name(owner),
         :ok <- check_name(repo),
         {:ok, pulls} <- pulls(owner, repo, token, opts[:state] || "all") do
      {:ok, Enum.map(pulls, &candidate("#{owner}/#{repo}", &1))}
    end
  end

  @doc """
  Pull requests matching a GitHub search query.

  The query is GitHub's own, passed through: `repo:owner/name label:design`,
  `author:me merged:>2024-01-01`, whatever the reader already knows how to
  write. `is:pr` is appended rather than required, because a search that
  quietly returned issues would fill a folder with documents that have no
  diff behind them.

  Search is a different endpoint with a different rate limit (30 a minute
  against 5000 an hour), and it caps at 1000 results however many pages you
  ask for. Both of those are GitHub's, not this module's, and both are worth
  knowing before pointing it at an organisation.
  """
  def search(query, token, opts \\ []) do
    case String.trim(query || "") do
      "" ->
        {:error, :empty_query}

      q ->
        q = if String.contains?(q, "is:pr"), do: q, else: q <> " is:pr"
        pages = min(opts[:pages] || @max_pages, @max_pages)

        Enum.reduce_while(1..pages, {:ok, []}, fn page, {:ok, acc} ->
          path =
            "/search/issues?q=#{URI.encode_www_form(q)}&per_page=#{@per_page}&page=#{page}"

          case get(path, token) do
            {:ok, %{"items" => []}} ->
              {:halt, {:ok, acc}}

            {:ok, %{"items" => items}} when length(items) < @per_page ->
              {:halt, {:ok, acc ++ items}}

            {:ok, %{"items" => items}} ->
              {:cont, {:ok, acc ++ items}}

            {:ok, _} ->
              {:halt, {:error, :no_results_field}}

            other ->
              {:halt, other}
          end
        end)
        |> case do
          {:ok, items} -> {:ok, Enum.map(items, &candidate(repo_of(&1), &1))}
          other -> other
        end
    end
  end

  # A search result does not carry owner/repo as such — it carries the API
  # URL of the repository it came from, which is the only place to get them.
  defp repo_of(%{"repository_url" => url}) when is_binary(url) do
    url |> String.split("/repos/", parts: 2) |> List.last()
  end

  defp repo_of(_), do: nil

  @doc """
  One row per pull request, for choosing from.

  Public because the shape is what the page is written against, and because
  a search result and a listing are two different JSON documents that have
  to arrive here looking the same.
  """
  def candidate(repo, p) do
    %{
      repo: repo,
      number: p["number"],
      title: p["title"] || "",
      url: p["html_url"],
      state: state_of(p),
      draft: p["draft"] == true,
      base: get_in(p, ["base", "ref"]),
      head: get_in(p, ["head", "ref"]),
      updated_at: p["updated_at"]
    }
  end

  # `state` is "open" or "closed"; whether a closed one was merged is a
  # different field, and the difference is the whole point of the filter.
  defp state_of(%{"merged_at" => at}) when is_binary(at), do: "merged"
  defp state_of(%{"pull_request" => %{"merged_at" => at}}) when is_binary(at), do: "merged"
  defp state_of(p), do: p["state"] || "open"

  @doc """
  The document each of these pull requests becomes.

  One request per pull request for the body, one more for the commits, run a
  few at a time — a hundred of them serially is minutes of waiting at a page
  that shows nothing. `on_item` is called as each lands, for the same reason.

  A pull request that cannot be fetched is returned as an error beside the
  ones that worked rather than failing the batch. Forty documents and a named
  failure is worth more than nothing and a reason.
  """
  def documents(candidates, token, opts \\ []) do
    commits? = Keyword.get(opts, :commits, true)
    files? = Keyword.get(opts, :files, true)
    total = length(candidates)

    candidates
    |> Task.async_stream(
      fn c ->
        out =
          case one_document(c, token, commits?, files?) do
            {:ok, doc} -> {:ok, doc}
            {:error, reason} -> {:error, {c, reason}}
          end

        # From inside the task, not from a pass over the finished results:
        # this is the only place that knows a document has landed while the
        # rest are still in flight, which is the whole point of reporting it.
        if is_function(opts[:on_item]), do: opts[:on_item].(c, total)
        out
      end,
      max_concurrency: Keyword.get(opts, :concurrency, 6),
      timeout: 120_000,
      on_timeout: :kill_task,
      ordered: true
    )
    |> Stream.zip(candidates)
    |> Enum.map(fn
      {{:ok, value}, _c} -> value
      {{:exit, reason}, c} -> {:error, {c, {:crashed, inspect(reason)}}}
    end)
    |> Enum.split_with(&match?({:ok, _}, &1))
    |> then(fn {ok, bad} ->
      %{
        documents: Enum.map(ok, fn {:ok, d} -> d end),
        failed: Enum.map(bad, fn {:error, pair} -> pair end)
      }
    end)
  end

  defp one_document(%{repo: repo, number: number} = c, token, commits?, files?) do
    with [owner, name] <- String.split(repo || "", "/", parts: 2),
         :ok <- check_name(owner),
         :ok <- check_name(name),
         {:ok, full} <- get("/repos/#{owner}/#{name}/pulls/#{number}", token) do
      item =
        %{
          ordinal: nil,
          number: number,
          title: full["title"] || c.title,
          body: full["body"] || "",
          url: full["html_url"] || c.url,
          changed_files: full["changed_files"]
        }
        |> then(fn i -> if commits?, do: with_commits(i, owner, name, token), else: i end)
        |> then(fn i -> if files?, do: with_files(i, owner, name, token), else: i end)

      {:ok,
       %{
         number: number,
         repo: repo,
         title: item.title,
         body: document(item),
         source_url: item.url
       }}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :bad_name}
    end
  end

  @doc """
  Put pull requests in stack order, or say why they are not a stack.

  Public because this is the part worth testing: everything else is HTTP.
  A stack that imports in the wrong order produces a method whose steps are
  in the wrong order, and nothing downstream can tell.
  """
  def order([], _default), do: {:error, :no_pull_requests}

  def order(pulls, default) do
    # Two pull requests from one branch is not a stack, and it is the shape
    # that gets through everything else: the walk terminates, the count comes
    # out right, and the order it produces is a guess. Caught here because
    # nothing downstream can see it.
    case duplicates(pulls, & &1["head"]["ref"]) do
      [] -> order_chain(pulls, default)
      dups -> {:error, {:duplicate_branches, dups}}
    end
  end

  defp duplicates(pulls, key) do
    pulls
    |> Enum.group_by(key)
    |> Enum.filter(fn {_ref, group} -> length(group) > 1 end)
    |> Enum.map(fn {ref, _} -> ref end)
    |> Enum.sort()
  end

  defp order_chain(pulls, default) do
    by_base = Map.new(pulls, fn p -> {p["base"]["ref"], p} end)

    case Enum.filter(pulls, &(&1["base"]["ref"] == default)) do
      [root] -> walk(root, by_base, pulls)
      [] -> {:error, {:no_root, default}}
      many -> {:error, {:many_roots, Enum.map(many, & &1["number"])}}
    end
  end

  defp walk(root, by_base, pulls) do
    {ordered, seen} = follow(root, by_base, [], MapSet.new())

    case Enum.reject(pulls, &MapSet.member?(seen, &1["number"])) do
      [] -> {:ok, Enum.map(Enum.with_index(ordered, 1), &to_item/1)}
      off -> {:error, {:off_chain, Enum.map(off, & &1["number"])}}
    end
  end

  defp follow(nil, _by_base, acc, seen), do: {Enum.reverse(acc), seen}

  defp follow(node, by_base, acc, seen) do
    if MapSet.member?(seen, node["number"]) do
      {Enum.reverse(acc), seen}
    else
      seen = MapSet.put(seen, node["number"])
      follow(Map.get(by_base, node["head"]["ref"]), by_base, [node | acc], seen)
    end
  end

  defp to_item({p, i}) do
    %{
      ordinal: i,
      number: p["number"],
      title: p["title"],
      body: p["body"] || "",
      url: p["html_url"]
    }
  end

  # --- landing it -----------------------------------------------------------

  @doc """
  Fetch a stack and file it as drafts in a folder.

  Idempotent on title: importing twice does not duplicate the stack, so a
  failed run can simply be run again. `on_item` is called per draft created,
  because this takes long enough that a page showing nothing is a page
  somebody reloads.
  """
  def import_stack(user_id, owner, repo, token, opts \\ []) do
    with {:ok, items} <- stack(owner, repo, token, opts),
         {:ok, folder} <- folder_for(user_id, opts[:folder] || "#{owner}/#{repo}") do
      have =
        folder.id
        |> works_in()
        |> MapSet.new()

      created =
        for item <- items, not MapSet.member?(have, title_for(item)) do
          {:ok, work} =
            Works.create_work(user_id, %{
              "title" => title_for(item),
              "body" => document(item),
              "source_url" => item.url
            })

          {:ok, _} = Folders.move_work(user_id, work.id, folder.id)
          if is_function(opts[:on_item]), do: opts[:on_item].(item, length(items))
          work
        end

      {:ok, %{folder: folder, created: length(created), total: length(items)}}
    end
  end

  # The ordinal goes in the title because that is where `Stacks.order/1`
  # looks, and because a reader opening the folder should see the order too.
  defp title_for(%{ordinal: n, title: title}) do
    if Regex.match?(~r/^\s*\d+\s*[.):-]/, title), do: title, else: "#{n}. #{title}"
  end

  @doc """
  The document one pull request becomes: its writeup, then its commit trail.

  Public because this is the part worth testing. Everything either side of it
  is HTTP, and what a chapter *says* is what every later pass reads — a
  document assembled wrongly produces a plausible step nothing downstream can
  tell is wrong.

  A pull request with an empty body is a document with nothing to read, and
  every later pass would quietly produce nothing from it. Saying so in the
  draft is better than an empty section the writer cannot explain.
  """
  def document(%{body: body, url: url, number: number} = item) do
    writeup =
      case String.trim(body || "") do
        "" -> "_This pull request (##{number}) has no description._\n\n#{url}\n"
        text -> text
      end

    writeup <> file_list(item) <> commit_trail(Map.get(item, :commits, []))
  end

  # Between the argument and the commits. The paths answer "what is this
  # actually about" in one glance, which the writeup sometimes does not and
  # a hundred commit subjects never do.
  @files_shown 60

  defp file_list(item) do
    case Map.get(item, :files, []) do
      [] ->
        ""

      {:error, reason} ->
        "\n\n---\n\n## Files changed\n\n_The file list could not be fetched " <>
          "(#{inspect(reason)}), so this says nothing about what was touched._\n"

      files ->
        total = Map.get(item, :changed_files) || length(files)
        shown = Enum.take(files, @files_shown)

        # Two separate caps can bite: GitHub pages the response at 100, and
        # this lists 60 of whatever came back. The header counts what is on
        # the page against what the pull request says it touched, so either
        # one being hit reads the same and neither is silent.
        head =
          if length(shown) < total,
            do: "#{total}, the first #{length(shown)} listed",
            else: "#{total}"

        "\n\n---\n\n## Files changed (#{head})\n\n" <>
          Enum.map_join(shown, "\n", &file_line/1)
    end
  end

  defp file_line(%{status: "renamed", path: path, was: was} = f),
    do: "- `#{was}` → `#{path}`#{counts(f)}"

  defp file_line(%{status: "added", path: path} = f), do: "- `#{path}`#{counts(f)} — new"
  defp file_line(%{status: "removed", path: path} = f), do: "- `#{path}`#{counts(f)} — deleted"
  defp file_line(%{path: path} = f), do: "- `#{path}`#{counts(f)}"

  defp counts(%{added: 0, removed: 0}), do: ""
  defp counts(%{added: a, removed: 0}), do: " +#{a}"
  defp counts(%{added: 0, removed: r}), do: " −#{r}"
  defp counts(%{added: a, removed: r}), do: " +#{a} −#{r}"

  # Bounded, and after the writeup, so that a chapter with a long history can
  # never push its own argument out of the window `Stacks.text_of/1` reads.
  @commit_cap 7_000

  defp commit_trail([]), do: ""

  defp commit_trail({:error, reason}) do
    "\n\n---\n\n## Commits\n\n_The commit trail could not be fetched " <>
      "(#{inspect(reason)}), so this chapter is its description alone._\n"
  end

  defp commit_trail(commits) do
    trail =
      commits
      |> Enum.map_join("\n\n", fn %{sha: sha, message: message} ->
        [subject | rest] = String.split(message, "\n", parts: 2)
        detail = rest |> List.first("") |> String.trim()

        "### #{subject}  (#{sha})" <> if(detail == "", do: "", else: "\n\n#{detail}")
      end)
      |> truncate(@commit_cap)

    "\n\n---\n\n## Commits (#{length(commits)})\n\n" <> trail <> "\n"
  end

  defp truncate(text, cap) do
    if String.length(text) <= cap,
      do: text,
      else: String.slice(text, 0, cap) <> "\n\n_[commit trail truncated]_"
  end

  defp folder_for(user_id, name) do
    import Ecto.Query

    case Repo.one(from f in Folders.Folder, where: f.user_id == ^user_id and f.name == ^name) do
      nil -> Folders.create_folder(user_id, %{name: name})
      folder -> {:ok, folder}
    end
  end

  defp works_in(folder_id) do
    import Ecto.Query
    Repo.all(from w in Works.Work, where: w.folder_id == ^folder_id, select: w.title)
  end

  @doc "What went wrong, in words a person can act on."
  def explain({:many_roots, numbers}),
    do:
      "#{length(numbers)} pull requests are based on the default branch (##{Enum.join(numbers, ", #")}). " <>
        "That is more than one stack, and this cannot tell which you meant."

  def explain({:no_root, branch}),
    do: "No open pull request is based on #{branch}, so there is no start to the chain."

  def explain({:off_chain, numbers}),
    do:
      "#{length(numbers)} pull request(s) are not on the chain: ##{Enum.join(numbers, ", #")}. " <>
        "A stack is each one based on the one before it."

  def explain({:duplicate_branches, refs}),
    do:
      "More than one open pull request comes from the same branch " <>
        "(#{Enum.join(refs, ", ")}). A stack is one pull request per branch."

  def explain(:no_pull_requests), do: "That repository has no open pull requests."
  def explain(:empty_query), do: "Write a search query first."

  def explain(:no_results_field),
    do: "GitHub answered the search with something this does not recognise."

  def explain({:crashed, _}), do: "That one crashed on the way in."
  def explain(:unauthorized), do: "GitHub rejected the token."

  def explain(:forbidden),
    do: "GitHub refused: the token may lack access, or you are rate limited."

  def explain(:not_found), do: "No such repository, or the token cannot see it."
  def explain(:bad_name), do: "Owner and repository must look like GitHub names."
  def explain({:http, status}), do: "GitHub answered #{status}."
  def explain({:transport, _}), do: "Could not reach GitHub."
  def explain(other), do: "Import failed: #{inspect(other)}"
end
