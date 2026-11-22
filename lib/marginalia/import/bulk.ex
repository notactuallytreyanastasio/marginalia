defmodule Marginalia.Import.Bulk do
  @moduledoc """
  Landing a pile of documents in a folder, whatever they came from.

  Two sources arrive here: pull requests fetched from GitHub and files
  dropped on the page. They have nothing in common by the time they reach
  this module — a title, some markdown, maybe an address it came from — and
  that is deliberate. Everything about where a document came from is
  finished before the landing starts, so there is one place that decides
  what an import *means*: what counts as a duplicate, what a bad document
  does to the rest of the batch, and what the writer is told afterwards.

  ## Nothing is all-or-nothing

  A batch of forty in which three are empty imports thirty-seven and names
  the three. The alternative — one bad file rolling back thirty-nine good
  ones — is the behaviour that makes people import in batches of one.

  ## Duplicates are decided by title, inside the folder

  Importing the same search twice should not double the folder. Title is a
  weak key and it is the right one here: it is what the reader sees, it is
  what they would call a duplicate, and both sources already put something
  meaningful in it. The check is scoped to the destination folder, so the
  same pull request landing in two different folders is two documents, which
  is what somebody doing that meant.

  ## Numbering is asked for, not assumed

  `Marginalia.Import.GitHub.import_stack/5` numbers its titles, because a
  stack is an order and `Marginalia.Stacks` reads that order back out of the
  title. A pile is not an order. Numbering it anyway would invent a sequence
  the reader did not choose and that later passes would take seriously.
  """

  require Logger

  import Ecto.Query

  alias Marginalia.{Folders, Repo, Works}
  alias Marginalia.Works.Upload

  @type doc :: %{
          required(:title) => String.t(),
          required(:body) => String.t(),
          optional(:source_url) => String.t() | nil
        }

  @doc """
  Create a work per document, in `folder`.

  Options:

    * `:folder` — the name of the folder to land in, created if it is not
      there. Without one the documents go to the root, loose.
    * `:number` — prefix each title with its position, `1. `, `2. `. Off by
      default; see the moduledoc.
    * `:on_item` — called as `fn title, index, total -> _ end` per document,
      because a hundred of these takes long enough that a page showing
      nothing is a page somebody reloads.

  Returns `%{folder:, created:, skipped:, failed:}` — counts of works made,
  titles already in the folder, and `{title, reason}` for everything that
  could not be made.
  """
  def land(user_id, docs, opts \\ []) do
    folder = folder_for(user_id, opts[:folder])
    have = titles_in(folder)
    total = length(docs)

    {created, skipped, failed} =
      docs
      |> Enum.with_index(1)
      |> Enum.reduce({[], [], []}, fn {doc, i}, {made, dup, bad} ->
        title = title_for(doc, i, opts[:number])

        result =
          if MapSet.member?(have, title),
            do: :skipped,
            else: create(user_id, folder, doc, title)

        if is_function(opts[:on_item]), do: opts[:on_item].(title, i, total)

        case result do
          :skipped -> {made, dup ++ [title], bad}
          {:ok, work} -> {made ++ [work], dup, bad}
          {:error, reason} -> {made, dup, bad ++ [{title, reason}]}
        end
      end)

    %{folder: folder, created: created, skipped: skipped, failed: failed}
  end

  defp create(user_id, folder, doc, title) do
    # The same gate the upload form uses, so a file dropped in a batch of
    # thirty gets the same answer it would have got on its own.
    case Upload.prepare(title, doc[:body], nil) do
      {:ok, attrs} ->
        attrs = Map.put(attrs, "source_url", doc[:source_url])

        case Works.create_work(user_id, attrs) do
          {:ok, work} ->
            if folder, do: Folders.move_work(user_id, work.id, folder.id)
            {:ok, work}

          {:error, %Ecto.Changeset{} = cs} ->
            {:error, changeset_reason(cs)}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, problem} ->
        {:error, problem}
    end
  end

  defp title_for(doc, _i, number) when number in [nil, false], do: clean(doc[:title])

  defp title_for(doc, i, _number) do
    title = clean(doc[:title])
    if Regex.match?(~r/^\s*\d+\s*[.):-]/, title), do: title, else: "#{i}. #{title}"
  end

  defp clean(nil), do: "Untitled"

  defp clean(title) do
    case title |> to_string() |> String.replace(~r/\s+/, " ") |> String.trim() do
      "" -> "Untitled"
      t -> String.slice(t, 0, 200)
    end
  end

  defp folder_for(_user_id, nil), do: nil

  defp folder_for(user_id, name) do
    case String.trim(to_string(name)) do
      "" ->
        nil

      name ->
        case Repo.one(from f in Folders.Folder, where: f.user_id == ^user_id and f.name == ^name) do
          nil ->
            case Folders.create_folder(user_id, %{name: name}) do
              {:ok, folder} -> folder
              {:error, _} -> nil
            end

          folder ->
            folder
        end
    end
  end

  defp titles_in(nil), do: MapSet.new()

  defp titles_in(folder) do
    Repo.all(from w in Works.Work, where: w.folder_id == ^folder.id, select: w.title)
    |> MapSet.new()
  end

  defp changeset_reason(%Ecto.Changeset{errors: errors}) do
    case errors do
      [{field, {msg, _}} | _] -> "#{field} #{msg}"
      [] -> :invalid
    end
  end

  # --- files dropped on the page --------------------------------------------

  @doc """
  A folder name for a pile of files that were not given one.

  Seven files called chapter-01 to chapter-07 belong together, and the
  thing they have in common is the part of the name before the number.
  That stem is the folder. When the names share nothing worth saying, the
  folder is named for the moment, because loose was the wrong answer: a
  pile dropped in one go is one thing, and the folder page is where the
  passes that read it as one thing live.
  """
  def folder_name_for(titles, now \\ DateTime.utc_now())

  def folder_name_for(titles, now) when is_list(titles) do
    stem =
      titles
      |> Enum.map(&to_string/1)
      |> common_prefix()
      |> String.replace(~r/[\s\d._-]+$/u, "")
      |> String.trim()

    if String.length(stem) >= 3,
      do: stem,
      else: "Imported " <> Calendar.strftime(now, "%Y-%m-%d %H:%M")
  end

  defp common_prefix([]), do: ""
  defp common_prefix([one]), do: one

  defp common_prefix([first | rest]) do
    Enum.reduce(rest, first, fn title, prefix ->
      prefix
      |> String.graphemes()
      |> Enum.zip(String.graphemes(title))
      |> Enum.take_while(fn {a, b} -> a == b end)
      |> Enum.map_join(&elem(&1, 0))
    end)
  end

  @doc """
  Documents in the order their names say, not the order a browser handed
  them over.

  A drop of seven files arrives in whatever order the file dialog listed
  them, which once was backwards, and numbering follows the order given,
  so chapter-01 became "7." and the folder read the book from the end.
  Natural order: digits compare as numbers, so 2 sorts before 10.
  """
  def in_name_order(docs) do
    Enum.sort_by(docs, fn doc ->
      doc[:title]
      |> to_string()
      |> String.downcase()
      |> String.split(~r/(\d+)/, include_captures: true)
      |> Enum.map(fn part ->
        case Integer.parse(part) do
          {n, ""} -> {0, n, ""}
          _ -> {1, 0, part}
        end
      end)
    end)
  end

  # --- what the page says about it ------------------------------------------

  @doc """
  A failure reason, in words.

  The reasons come from three layers — the word gate, Ecto, and the
  segmenter — and a page that printed them raw would tell a writer their
  file failed with `{:too_long, 143_204}`.
  """
  def explain(:empty), do: "there is no text in it"
  def explain({:too_long, words}), do: "#{words} words, over the limit"
  def explain(:no_sections), do: "no text that could be split into sections"
  def explain(reason) when is_binary(reason), do: reason
  def explain(reason), do: inspect(reason)

  @doc """
  Keep the candidates whose title matches `pattern`.

  Returns `{:ok, kept}` or `{:error, message}` for a pattern that will not
  compile — a half-typed regex is the normal state of a regex box, and the
  page has to be able to say what is wrong with it rather than crash.

  The title is truncated before matching. A pattern with catastrophic
  backtracking in it hangs the scheduler running it, and `:re` takes no
  timeout from Elixir; bounding the subject is the one lever there is, and
  200 characters of title is short enough that no pattern can spend long in
  it.
  """
  def by_title(candidates, pattern) do
    case String.trim(to_string(pattern || "")) do
      "" ->
        {:ok, candidates}

      pattern ->
        case Regex.compile(pattern, "i") do
          {:ok, re} ->
            {:ok,
             Enum.filter(candidates, &Regex.match?(re, String.slice(&1.title || "", 0, 200)))}

          {:error, {reason, at}} ->
            {:error, "#{reason} at character #{at}"}

          {:error, reason} ->
            {:error, inspect(reason)}
        end
    end
  end
end
