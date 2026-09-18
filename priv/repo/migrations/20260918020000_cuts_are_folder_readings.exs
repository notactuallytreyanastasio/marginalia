defmodule Marginalia.Repo.Migrations.CutsAreFolderReadings do
  use Ecto.Migration

  def change do
    # A cut began as a hand-picked set of passages and that was the wrong
    # unit. The thing a writer already groups is a folder, and the folder is
    # what they want read: these eight documents are one case, so what do
    # they say together? Higher order falls out of the same move — a folder
    # of folders is read over its children's readings rather than over their
    # text, which is both the only affordable way to do it and the only
    # honest one.
    alter table(:cuts) do
      add :scope, :string, null: false, default: "folder"
      # who was read: works for a leaf folder, child folders above that
      add :members, :map
    end

    # One reading per folder. Re-reading replaces it; a folder with six
    # readings is a folder nobody can quote.
    create unique_index(:cuts, [:user_id, :folder_id],
             where: "folder_id IS NOT NULL",
             name: :cuts_one_per_folder_index
           )
  end
end
