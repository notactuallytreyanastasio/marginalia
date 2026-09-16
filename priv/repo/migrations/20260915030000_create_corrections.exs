defmodule Marginalia.Repo.Migrations.CreateCorrections do
  use Ecto.Migration

  # The chat's system prompt has been telling the model to call
  # `record_correction` since the first version. The tool did not exist, so
  # every promise to "never bring that up again" was empty. This is where it
  # goes now.
  def change do
    create table(:corrections) do
      add :work_id, references(:works, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :about, :text, null: false
      add :ruling, :text
      add :section_ordinal, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:corrections, [:work_id])
  end
end
