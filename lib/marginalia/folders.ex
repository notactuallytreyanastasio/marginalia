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
  """

  import Ecto.Query

  alias Marginalia.Repo
  alias Marginalia.Folders.Folder
  alias Marginalia.Works
  alias Marginalia.Works.Work

  @doc "Every folder this writer has, flat, in sibling order."
  def list_folders(user_id) do
    Folder
    |> where([f], f.user_id == ^user_id)
    |> order_by([f], asc: fragment("lower(?)", f.name), asc: f.id)
    |> Repo.all()
  end

  @doc "Fetch a folder this user owns, or nil."
  def get_folder(user_id, id) do
    case cast_id(id) do
      nil -> nil
      id -> Repo.one(from f in Folder, where: f.user_id == ^user_id and f.id == ^id)
    end
  end

  def change_folder(folder \\ %Folder{}, attrs \\ %{}), do: Folder.changeset(folder, attrs)

  @doc """
  Make a folder, optionally inside another one.

  A `parent_id` the user does not own is dropped rather than refused: the only
  way to send one is to forge it, and a forged parent should land the folder
  at the root, not hand back a map of which ids exist.
  """
  def create_folder(user_id, attrs, opts \\ []) do
    parent_id = attrs |> get_attr(:parent_id) |> owned_parent(user_id)

    %Folder{user_id: user_id}
    |> Folder.changeset(%{name: get_attr(attrs, :name), parent_id: parent_id})
    |> Repo.insert(opts)
  end

  def rename_folder(user_id, id, name) do
    case get_folder(user_id, id) do
      nil -> {:error, :not_found}
      folder -> folder |> Folder.changeset(%{name: name}) |> Repo.update()
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
          from(w in Work, where: w.folder_id == ^folder.id)
          |> Repo.update_all(set: [folder_id: folder.parent_id])

          from(f in Folder, where: f.parent_id == ^folder.id)
          |> Repo.update_all(set: [parent_id: folder.parent_id])

          Repo.delete!(folder)
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
      folder
      |> Ecto.Changeset.change(parent_id: parent_id)
      |> Folder.changeset(%{name: folder.name})
      |> Repo.update()
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
        work
        |> Ecto.Changeset.change(folder_id: owned_parent(folder_id, user_id))
        |> Repo.update()
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
    from(w in Work,
      where: w.user_id == ^user_id and not is_nil(w.collection) and is_nil(w.folder_id)
    )
    |> Repo.aggregate(:count)
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
    loose =
      from(w in Work,
        where: w.user_id == ^user_id and not is_nil(w.collection) and is_nil(w.folder_id)
      )
      |> Repo.all()

    case Enum.group_by(loose, & &1.collection) do
      groups when groups == %{} ->
        {:ok, 0}

      groups ->
        Repo.transaction(fn ->
          parent = parent_name && get_or_create(user_id, parent_name, nil)

          Enum.reduce(groups, 0, fn {collection, works}, filed ->
            folder = get_or_create(user_id, collection, parent && parent.id)
            ids = Enum.map(works, & &1.id)

            {n, _} =
              from(w in Work, where: w.id in ^ids)
              |> Repo.update_all(set: [folder_id: folder.id])

            filed + n
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
      {:error, _changeset} -> Repo.one!(sibling(user_id, name, parent_id))
    end
  end

  defp sibling(user_id, name, nil),
    do:
      from(f in Folder, where: f.user_id == ^user_id and f.name == ^name and is_nil(f.parent_id))

  defp sibling(user_id, name, parent_id),
    do:
      from(f in Folder,
        where: f.user_id == ^user_id and f.name == ^name and f.parent_id == ^parent_id
      )

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
        folder
        |> Ecto.Changeset.change(
          published_at: DateTime.utc_now() |> DateTime.truncate(:second),
          slug: folder.slug || mint_slug(folder.name)
        )
        |> Repo.update()

      true ->
        {:error, :not_found}
    end
  end

  @doc "Take it back off the public site. The slug is kept, so re-publishing restores the same URL."
  def unpublish(user_id, id) do
    case get_folder(user_id, id) do
      nil -> {:error, :not_found}
      folder -> folder |> Ecto.Changeset.change(published_at: nil) |> Repo.update()
    end
  end

  @doc "A published folder by its slug, for anybody, or nil."
  def get_published(slug) when is_binary(slug) do
    Repo.one(from f in Folder, where: f.slug == ^slug and not is_nil(f.published_at))
  end

  def get_published(_), do: nil

  @doc "Every published folder, newest first."
  def published do
    Folder
    |> where([f], not is_nil(f.published_at))
    |> order_by([f], desc: f.published_at)
    |> Repo.all()
  end

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
    if Repo.exists?(from f in Folder, where: f.slug == ^base) do
      base <> "-" <> (:crypto.strong_rand_bytes(3) |> Base.url_encode64(padding: false))
    else
      base
    end
  end
end
