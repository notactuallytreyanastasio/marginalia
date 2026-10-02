defmodule Marginalia.Folders do
  @moduledoc """
  Buckets of drafts.

  A folder is a *place*, not a property. That is the whole reason this is a
  table with a `parent_id` instead of another string field on `works` beside
  `collection`. A collection names something several drafts together *are* —
  a case, with an opinion and a dissent playing roles inside it — and it is
  public. A folder is somewhere one writer put some drafts, it nests, and it
  is nobody else's business. Reusing `collection` for both would have made
  dropping a draft into "Reading pile" publish it on /cases.

  Everything here is scoped by `user_id`, the same discipline as `Works`: no
  function returns or moves a folder without checking who is asking.

  The SQL is built in Temper, with Alloy, in
  `temper/marginalia-core/src/folders.temper.md`, and run by
  `Marginalia.Alloy`. This module decides what to run and in what order,
  and makes rows into `Folder` structs; it writes no SQL itself.
  """

  alias Marginalia.{Alloy, Repo}
  alias Marginalia.Folders.{Folder, Invalid}
  alias Marginalia.Works
  alias Temper.MarginaliaCore, as: Core

  @taken "there is already a folder with that name here"
  @sibling_indexes ~w(folders_sibling_name_index folders_root_name_index)

  @doc "Every folder this writer has, flat, in sibling order."
  def list_folders(user_id), do: all(Core.listFolders(user_id))

  @doc "Fetch a folder this user owns, or nil."
  def get_folder(user_id, id) do
    case cast_id(id) do
      nil -> nil
      id -> one(Core.getFolder(user_id, id))
    end
  end

  @doc "A writer's folder by name, anywhere in the tree, or nil. The importers file into it."
  def get_folder_by_name(user_id, name), do: one(Core.folderByName(user_id, name))

  @doc "Folders by id, whoever owns them, keyed by id: what `preload(:folder)` used to fetch."
  def folders_by_id([]), do: %{}

  def folders_by_id(ids) do
    ids |> Enum.uniq() |> Core.foldersByIds() |> all() |> Map.new(&{&1.id, &1})
  end

  @doc """
  Make a folder, optionally inside another one.

  A `parent_id` the user does not own is dropped rather than refused: the only
  way to send one is to forge it, and a forged parent should land the folder
  at the root, not hand back a map of which ids exist.
  """
  def create_folder(user_id, attrs, opts \\ []) do
    parent_id = attrs |> get_attr(:parent_id) |> owned_parent(user_id)
    name = attrs |> get_attr(:name) |> to_string()

    write(Core.createFolder(user_id, name, parent_id), savepoint: opts[:mode] == :savepoint)
  end

  def rename_folder(user_id, id, name) do
    case get_folder(user_id, id) do
      nil ->
        {:error, :not_found}

      folder ->
        prepared = Core.renameFolder(user_id, folder.id, to_string(name))

        # an unchanged name is no write, as an unchanged Ecto changeset was none
        if prepared.statement && String.trim(to_string(name)) == folder.name,
          do: {:ok, folder},
          else: write(prepared)
    end
  end

  @doc """
  Delete a folder and lift everything it held into its parent.

  Deleting a bucket is not deleting what is in it. A writer reaching for the
  x on a folder is tidying, and losing six drafts to a tidy-up is the kind of
  thing you only forgive software once.
  """
  def delete_folder(user_id, id) do
    case get_folder(user_id, id) do
      nil ->
        {:error, :not_found}

      folder ->
        Repo.transaction(fn ->
          [lift_works, lift_folders, delete] =
            Enum.to_list(Core.deleteFolder(folder.id, folder.parent_id))

          Alloy.query!(lift_works)
          Alloy.query!(lift_folders)
          [row] = Alloy.query!(delete)
          Folder.from_row(row)
        end)
    end
  end

  @doc """
  Move a folder under another one, or to the root with `nil`.

  Refuses to put a folder inside itself or inside one of its own descendants.
  The browser already refuses — the drop target is inside the dragged element,
  so it cannot be hit — but the check lives here because that is a fact about
  the tree, not about the mouse.
  """
  def move_folder(user_id, id, parent_id) do
    with %Folder{} = folder <- get_folder(user_id, id) || {:error, :not_found},
         parent_id = owned_parent(parent_id, user_id),
         false <- parent_id == folder.id,
         false <- descendant?(user_id, parent_id, folder.id) do
      if parent_id == folder.parent_id,
        do: {:ok, folder},
        else: write_statement(Core.moveFolder(user_id, folder.id, parent_id), [])
    else
      true -> {:error, :cycle}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Put a draft in a folder, or take it out of one with `nil`."
  def move_work(user_id, work_id, folder_id) do
    case Works.get_work(user_id, work_id) do
      nil ->
        {:error, :not_found}

      work ->
        case owned_parent(folder_id, user_id) do
          same when same == work.folder_id ->
            {:ok, work}

          folder_id ->
            Alloy.query!(Core.moveWork(user_id, work.id, folder_id))
            {:ok, Works.get_work(user_id, work.id)}
        end
    end
  end

  @doc """
  The whole tree for one writer, in one pair of queries.

  Shape is `%{folders: [node], works: [work]}`, where a node is that map plus
  `:folder` and `:count` — how many drafts sit in it *and* below it, which is
  the number a collapsed row has to be able to show.

  Two queries and an assembly in Elixir, not a recursive CTE: a person has
  tens of folders, and the query that reads plainly is worth more here than
  the one that would still read plainly at a million.
  """
  def tree(user_id) do
    by_parent =
      user_id
      |> list_folders()
      |> Enum.group_by(& &1.parent_id)

    by_folder =
      user_id
      |> Works.list_works()
      |> Enum.group_by(& &1.folder_id)

    build(nil, by_parent, by_folder)
  end

  defp build(parent_id, by_parent, by_folder) do
    folders =
      by_parent
      |> Map.get(parent_id, [])
      |> Enum.map(fn folder ->
        node = build(folder.id, by_parent, by_folder)
        count = length(node.works) + Enum.sum(Enum.map(node.folders, & &1.count))
        node |> Map.put(:folder, folder) |> Map.put(:count, count)
      end)

    %{folders: folders, works: Map.get(by_folder, parent_id, [])}
  end

  @doc """
  How many drafts the backfill would move right now.

  The page uses this to decide whether to offer the button at all: an offer
  to tidy a pile that is already tidy is noise.
  """
  def unfiled_collection_count(user_id) do
    [%{count: n}] = Alloy.query!(Core.unfiledCount(user_id))
    n
  end

  @doc """
  File every draft that already belongs to a named collection into a folder
  for it, gathered under one parent.

  The grouping does not have to be invented. A writer who has been importing
  cases has already told us which drafts go together — that is what
  `collection` is — and making them drag that same grouping in by hand is
  asking them to say it twice.

  Drafts with no collection are left at the root on purpose. The root *is*
  the uncategorised pile; a folder named "Uncategorised" only moves it
  somewhere you have to click to see.

  Idempotent, and it never overrules a person: a draft that is already in a
  folder stays where it was put. Returns `{:ok, filed_count}`.
  """
  def backfill_from_collections(user_id, parent_name \\ "Cases") do
    loose = Alloy.query!(Core.looseWorkCollections(user_id))

    case Enum.group_by(loose, & &1.collection) do
      groups when groups == %{} ->
        {:ok, 0}

      groups ->
        Repo.transaction(fn ->
          parent = parent_name && get_or_create(user_id, parent_name, nil)

          Enum.reduce(groups, 0, fn {collection, works}, filed ->
            folder = get_or_create(user_id, collection, parent && parent.id)
            ids = Enum.map(works, & &1.id)

            filed + Alloy.query!(Core.fileWorks(ids, folder.id))
          end)
        end)
    end
  end

  # Insert, or take the one already there. The unique index is the authority
  # on whether a sibling with this name exists — checking first and inserting
  # after is the same race with extra steps.
  #
  # `mode: :savepoint` is the part that is easy to leave out and impossible to
  # miss once it bites. Postgres aborts the whole transaction on a constraint
  # violation, so without a savepoint the very next query in the backfill —
  # the one fetching the folder that already existed — comes back
  # `25P02 in_failed_sql_transaction` and the rescue path is unreachable.
  defp get_or_create(user_id, name, parent_id) do
    case create_folder(user_id, %{name: name, parent_id: parent_id}, mode: :savepoint) do
      {:ok, folder} -> folder
      {:error, %Invalid{}} -> one!(Core.sibling(user_id, name, parent_id))
    end
  end

  @doc "Whether `id` sits somewhere under `ancestor_id`. `nil` is under nothing."
  def descendant?(_user_id, nil, _ancestor_id), do: false

  def descendant?(user_id, id, ancestor_id) do
    case get_folder(user_id, id) do
      nil -> false
      %Folder{parent_id: ^ancestor_id} -> true
      %Folder{parent_id: nil} -> false
      %Folder{parent_id: parent_id} -> descendant?(user_id, parent_id, ancestor_id)
    end
  end

  # A parent the caller does not own is no parent at all.
  defp owned_parent(nil, _user_id), do: nil
  defp owned_parent("", _user_id), do: nil
  defp owned_parent("root", _user_id), do: nil

  defp owned_parent(id, user_id) do
    case get_folder(user_id, id) do
      nil -> nil
      folder -> folder.id
    end
  end

  defp get_attr(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, to_string(key))
  end

  defp cast_id(id) when is_integer(id), do: id

  defp cast_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp cast_id(_), do: nil

  # ==========================================================================
  # Publishing
  # ==========================================================================

  @doc """
  Make a folder readable by somebody with no account, and mint its slug.

  Two conditions, both required, for the same reason `Cases.published/0` has
  them: this writer's contracts and employment agreements live in folders
  beside the one being published, so publishing by accident has to be
  impossible. The folder must belong to the account this deploy belongs to,
  and somebody must ask for it by name.

  The slug is derived from the folder name rather than random, because this
  is the one URL here meant to be sent to people, and it is minted once so
  that renaming the folder afterwards does not break a link already sent.
  """
  def publish(user_id, id) do
    owner = Marginalia.Accounts.owner()

    cond do
      is_nil(owner) or owner.id != user_id ->
        {:error, :not_owner}

      folder = get_folder(user_id, id) ->
        [row] =
          Alloy.query!(Core.publish(user_id, folder.id, folder.slug || mint_slug(folder.name)))

        {:ok, Folder.from_row(row)}

      true ->
        {:error, :not_found}
    end
  end

  @doc "Take it back off the public site. The slug is kept, so re-publishing restores the same URL."
  def unpublish(user_id, id) do
    case get_folder(user_id, id) do
      nil -> {:error, :not_found}
      %Folder{published_at: nil} = folder -> {:ok, folder}
      folder -> write_statement(Core.unpublish(user_id, folder.id), [])
    end
  end

  @doc "A published folder by its slug, for anybody, or nil."
  def get_published(slug) when is_binary(slug), do: one(Core.publishedBySlug(slug))

  def get_published(_), do: nil

  @doc "Every published folder, newest first."
  def published, do: all(Core.published())

  defp mint_slug(name) do
    base =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")
      |> String.slice(0, 60)

    base = if base == "", do: "stack", else: base

    # A second folder that slugs to the same thing gets a suffix rather than
    # a constraint violation the caller cannot do anything about.
    if Alloy.query!(Core.slugTaken(base)) != [] do
      base <> "-" <> (:crypto.strong_rand_bytes(3) |> Base.url_encode64(padding: false))
    else
      base
    end
  end

  # ==========================================================================
  # Running Alloy's statements
  # ==========================================================================

  # A write a changeset may refuse: Alloy's validation errors, or the row.
  defp write(prepared, opts \\ [])

  defp write(%Core.Prepared{statement: nil, errors: errors}, _opts) do
    {:error, %Invalid{errors: Enum.group_by(errors, &String.to_atom(&1.field), & &1.message)}}
  end

  defp write(%Core.Prepared{statement: statement}, opts), do: write_statement(statement, opts)

  # The sibling-name indexes are the one rule only Postgres can check; their
  # violation is the same error on `name` the Ecto changeset reported.
  defp write_statement(statement, opts) do
    case Alloy.query(statement, opts) do
      {:ok, [row]} ->
        {:ok, Folder.from_row(row)}

      {:ok, []} ->
        {:error, :not_found}

      {:error, %Postgrex.Error{postgres: %{code: :unique_violation, constraint: c}}}
      when c in @sibling_indexes ->
        {:error, %Invalid{errors: %{name: [@taken]}}}

      {:error, error} ->
        raise error
    end
  end

  defp all(statement), do: statement |> Alloy.query!() |> Enum.map(&Folder.from_row/1)

  defp one(statement) do
    case all(statement) do
      [] -> nil
      [folder] -> folder
      many -> raise ArgumentError, "expected at most one folder, got #{length(many)}"
    end
  end

  defp one!(statement), do: one(statement) || raise(ArgumentError, "expected a folder, got none")
end
