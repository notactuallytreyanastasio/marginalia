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

  Returns `{:ok, [%{ordinal:, title:, body:, url:, number:}]}`, or an error
  naming what is wrong with the stack rather than a bare failure.
  """
  def stack(owner, repo, token, opts \\ []) do
    with :ok <- check_name(owner),
         :ok <- check_name(repo),
         {:ok, default} <- default_branch(owner, repo, token),
         {:ok, pulls} <- pulls(owner, repo, token, opts[:state] || "open") do
      order(pulls, default)
    end
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
              "body" => body_for(item),
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

  # A pull request with an empty body is a document with nothing to read, and
  # every later pass would quietly produce nothing from it. Saying so in the
  # draft is better than an empty section the writer cannot explain.
  defp body_for(%{body: body, url: url, number: number}) do
    case String.trim(body || "") do
      "" -> "_This pull request (##{number}) has no description._\n\n#{url}\n"
      text -> text
    end
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
  def explain(:unauthorized), do: "GitHub rejected the token."

  def explain(:forbidden),
    do: "GitHub refused: the token may lack access, or you are rate limited."

  def explain(:not_found), do: "No such repository, or the token cannot see it."
  def explain(:bad_name), do: "Owner and repository must look like GitHub names."
  def explain({:http, status}), do: "GitHub answered #{status}."
  def explain({:transport, _}), do: "Could not reach GitHub."
  def explain(other), do: "Import failed: #{inspect(other)}"
end
