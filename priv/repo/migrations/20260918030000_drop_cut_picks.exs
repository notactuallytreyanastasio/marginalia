defmodule Marginalia.Repo.Migrations.DropCutPicks do
  use Ecto.Migration

  # Hand-picked passages were the wrong unit and never held a row. The folder
  # is what a writer already groups, so the folder is what gets read.
  def up, do: drop_if_exists(table(:cut_picks))

  def down do
    create table(:cut_picks) do
      add :cut_id, references(:cuts, on_delete: :delete_all), null: false
      add :work_id, references(:works, on_delete: :delete_all), null: false
      add :block_ref, :string, null: false
      add :quote, :text, null: false
      add :ordinal, :integer, null: false, default: 0
      timestamps(type: :utc_datetime)
    end
  end
end
