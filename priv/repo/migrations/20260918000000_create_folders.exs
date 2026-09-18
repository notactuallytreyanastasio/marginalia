defmodule Marginalia.Repo.Migrations.CreateFolders do
  use Ecto.Migration

  def change do
    create table(:folders) do
      add :name, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :parent_id, references(:folders, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:folders, [:user_id])
    create index(:folders, [:parent_id])

    # Two siblings with the same name make a tree you cannot read out loud.
    # Postgres treats NULLs as distinct inside a unique index, so the root
    # level does not fall out of the three-column one for free and needs a
    # partial index of its own.
    create unique_index(:folders, [:user_id, :parent_id, :name],
             where: "parent_id IS NOT NULL",
             name: :folders_sibling_name_index
           )

    create unique_index(:folders, [:user_id, :name],
             where: "parent_id IS NULL",
             name: :folders_root_name_index
           )

    # `nilify_all` rather than `delete_all`: deleting a bucket must never
    # delete the drafts in it. `Folders.delete_folder/2` lifts the contents
    # into the parent first; this is the backstop for anything that does not.
    alter table(:works) do
      add :folder_id, references(:folders, on_delete: :nilify_all)
    end

    create index(:works, [:folder_id])
  end
end
