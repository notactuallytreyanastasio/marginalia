defmodule Marginalia.Repo.Migrations.CreateDocumentSummaries do
  use Ecto.Migration

  @moduledoc """
  The whole document, read two ways at once.

  One row per work rather than a history: a document summary is derived from
  the sections and is cheap to rebuild, so what matters is whether it is
  current, not what it said in March. The fingerprint over the section
  summaries is what answers that.
  """

  def change do
    create table(:document_summaries) do
      add :work_id, references(:works, on_delete: :delete_all), null: false

      # the composing prong: what the document does, built up from its parts
      add :summary, :text
      add :throughline, :text
      add :movements, {:array, :map}, default: []

      # the decomposing prong: the rules it is working under, found by
      # reading down from the whole rather than up from the sections
      add :guidelines, {:array, :map}, default: []
      add :tensions, {:array, :map}, default: []

      add :fingerprint, :string
      add :dropped, {:array, :string}, default: []

      timestamps(type: :utc_datetime)
    end

    create unique_index(:document_summaries, [:work_id])
  end
end
