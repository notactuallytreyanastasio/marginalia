defmodule Marginalia.Repo.Migrations.CreateStackSteps do
  use Ecto.Migration

  def change do
    # A stack is an ordered folder: documents that build one thing, read in
    # the order they were written. A step is one document read *forwards* —
    # told only what came before it — which is the reading a newcomer can
    # follow and the one no single document contains.
    create table(:stack_steps) do
      add :folder_id, references(:folders, on_delete: :delete_all), null: false
      add :work_id, references(:works, on_delete: :delete_all), null: false
      add :ordinal, :integer, null: false

      # what the thing can do after this step that it could not before
      add :capability, :text
      # earlier ordinals this step stands on: what makes the order load-bearing
      add :requires, {:array, :integer}, default: []
      add :lesson, :text
      # the obvious approach that is wrong here, with the sentence proving it
      add :pitfall, :text
      add :pitfall_quote, :text
      add :excerpts, :map

      # the document as it was when read, so a changed source shows as stale
      add :fingerprint, :string
      add :dropped, {:array, :string}, default: []

      timestamps(type: :utc_datetime)
    end

    create unique_index(:stack_steps, [:folder_id, :work_id])
    create index(:stack_steps, [:folder_id])
  end
end
