defmodule Marginalia.Git do
  @moduledoc """
  A draft's history as an actual git repository, one per work.

  Not a metaphor and not a reimplementation: `git` on the PATH, a working
  tree per draft, one commit per accepted change. The revisions table already
  holds the paragraph-level patches and is what the Changes tab reads; this
  is the whole document, in a format the writer can clone, `git log -p`,
  bisect, or hand to anything that understands a repository.

  ## Off unless configured, on purpose

  `config :marginalia, :draft_repo_root` has no default. Writing repositories
  to a path nobody chose is how this feature silently loses everything: the
  production container has no volumes, so anything written inside it is
  destroyed by the next deploy and the loss looks exactly like success. An
  unconfigured deploy therefore does not pretend to keep history — `enabled?/0`
  is false, every call returns `{:error, :not_configured}`, and the page says
  so rather than showing a log that will be empty tomorrow.

  ## Why commits happen after the transaction, not inside it

  A commit is a side effect on a filesystem and cannot be rolled back with
  the database. Committing inside `Works.replace_block/4`'s transaction would
  leave a commit describing a write that never landed. So the database is the
  record and git follows it; if a commit fails the draft is still correct and
  the failure is reported rather than taking the edit down with it.
  """

  require Logger

  alias Marginalia.Works
  alias Marginalia.Works.Work

  # NOT `@file`: that is a reserved compiler directive that sets the source
  # file name for diagnostics, so reading it back gives nil and every path
  # built from it blows up in Path.join/2.
  @draft_file "draft.md"

  @doc "Whether this deploy keeps git history for drafts."
  def enabled?, do: is_binary(root()) and root() != ""

  @doc "Where draft repositories live, or nil."
  def root, do: Application.get_env(:marginalia, :draft_repo_root)

  @doc "The working tree for one draft."
  def path(%Work{slug: slug}), do: if(enabled?(), do: Path.join(root(), slug))

  @doc """
  Record the draft as it now stands.

  `message` is the commit subject. Idempotent in the way git is: a commit
  with nothing staged is not an error and not a commit, it is `:unchanged`,
  which is the honest answer when a writer saves a paragraph they did not
  actually alter.
  """
  def commit(%Work{} = work, message, opts \\ []) do
    with :ok <- check_enabled(),
         {:ok, dir} <- ensure_repo(work),
         :ok <- write(dir, work) do
      case run(dir, ["status", "--porcelain"]) do
        {:ok, ""} ->
          {:ok, :unchanged}

        {:ok, _dirty} ->
          with {:ok, _} <- run(dir, ["add", @draft_file]),
               {:ok, _} <- run(dir, commit_args(message, opts)),
               {:ok, sha} <- run(dir, ["rev-parse", "--short", "HEAD"]) do
            {:ok, String.trim(sha)}
          end

        other ->
          other
      end
    end
  end

  @doc "The commits of a draft, newest first."
  def log(%Work{} = work, limit \\ 50) do
    with :ok <- check_enabled(),
         {:ok, dir} <- existing(work),
         {:ok, out} <-
           run(dir, [
             "log",
             "--max-count=#{limit}",
             "--pretty=format:%h%x1f%ad%x1f%s",
             "--date=iso"
           ]) do
      entries =
        out
        |> String.split("\n", trim: true)
        |> Enum.map(fn line ->
          case String.split(line, "\x1f") do
            [sha, date, subject] -> %{sha: sha, date: date, subject: subject}
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      {:ok, entries}
    end
  end

  @doc "The patch for one commit, as git prints it."
  def show(%Work{} = work, sha) do
    with :ok <- check_enabled(),
         :ok <- check_sha(sha),
         {:ok, dir} <- existing(work) do
      run(dir, ["show", "--format=%h %ad%n%s%n", "--date=iso", sha])
    end
  end

  # --- the repository --------------------------------------------------------

  defp ensure_repo(%Work{} = work) do
    dir = path(work)

    cond do
      File.dir?(Path.join(dir, ".git")) ->
        {:ok, dir}

      true ->
        with :ok <- File.mkdir_p(dir),
             {:ok, _} <- run(dir, ["init", "--quiet", "--initial-branch=main"]),
             {:ok, _} <- run(dir, ["config", "user.name", "Marginalia"]),
             {:ok, _} <- run(dir, ["config", "user.email", "marginalia@localhost"]) do
          {:ok, dir}
        end
    end
  end

  defp existing(%Work{} = work) do
    dir = path(work)
    if File.dir?(Path.join(dir, ".git")), do: {:ok, dir}, else: {:error, :no_repo}
  end

  # The document, plus the front matter that says which draft this is — a bare
  # repository of untitled markdown is hard to identify a year later.
  defp write(dir, %Work{} = work) do
    contents = """
    ---
    title: #{work.title}
    slug: #{work.slug}
    words: #{work.word_count}
    ---

    #{work.body}
    """

    File.write(Path.join(dir, @draft_file), contents)
  end

  defp commit_args(message, opts) do
    author = opts[:author]

    ["commit", "--quiet", "--message", subject(message)] ++
      if(is_binary(author) and author != "", do: ["--author", author], else: [])
  end

  # One line. A commit subject carrying a paragraph of prose is a commit
  # subject nothing will render.
  defp subject(message) do
    message
    |> to_string()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 200)
    |> case do
      "" -> "Edit"
      s -> s
    end
  end

  defp check_enabled, do: if(enabled?(), do: :ok, else: {:error, :not_configured})

  # A sha goes on a command line, so it is checked rather than escaped.
  defp check_sha(sha) when is_binary(sha) do
    if Regex.match?(~r/^[0-9a-f]{4,40}$/, sha), do: :ok, else: {:error, :bad_sha}
  end

  defp check_sha(_), do: {:error, :bad_sha}

  # System.cmd with an argument list, never a shell string: a draft's title
  # goes into a commit message and titles contain quotes.
  defp run(dir, args) do
    case System.cmd("git", args, cd: dir, stderr_to_stdout: true) do
      {out, 0} ->
        {:ok, out}

      {out, code} ->
        Logger.warning(
          "marginalia: git #{inspect(args)} failed (#{code}): #{String.slice(out, 0, 300)}"
        )

        {:error, {:git, code, String.slice(out, 0, 300)}}
    end
  end

  @doc """
  Commit after a change the writer accepted.

  Called from the page once the database transaction has returned, never
  inside it. A failure here is logged and reported, and deliberately does not
  fail the edit: the draft is already correct, and losing a writer's
  paragraph because a filesystem was full would be the worse outcome.
  """
  def record(work_id, message, opts \\ []) do
    if enabled?() do
      work = Works.get_work!(opts[:user_id] || raise("record/3 needs :user_id"), work_id)
      commit(work, message, opts)
    else
      {:error, :not_configured}
    end
  end
end
