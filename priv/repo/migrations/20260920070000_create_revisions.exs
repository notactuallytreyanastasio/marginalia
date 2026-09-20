defmodule Marginalia.Repo.Migrations.CreateRevisions do
  use Ecto.Migration

  @moduledoc """
  Every change to a draft's prose, in order, as a patch.

  Paragraph granularity, not whole-body snapshots. A draft here runs to
  twenty thousand words and an edit moves a sentence; storing the document
  twice per keystroke-sized change would be most of a megabyte an afternoon.
  `before` and `after` hold the one paragraph that moved, which is enough to
  replay the draft forward from its baseline and enough to render a diff.
  """

  def change do
    alter table(:works) do
      # the prose as it arrived, so "what has changed" has something to be
      # measured against once the body itself has moved on
      add :baseline_body, :text
    end

    create table(:revisions) do
      add :work_id, references(:works, on_delete: :delete_all), null: false
      add :section_id, references(:sections, on_delete: :nilify_all)

      # kept alongside section_id because a section can be deleted and the
      # history of the draft should survive it
      add :section_ordinal, :integer

      add :seq, :integer, null: false
      add :before, :text, null: false
      add :after, :text, null: false

      # "edit" or "rewrite" — where the change came from, which is the
      # question asked of this table most often
      add :origin, :string, null: false, default: "edit"

      # for a rewrite, the candidate's own label: "cuts the gloss"
      add :note, :string

      timestamps(type: :utc_datetime)
    end

    create index(:revisions, [:work_id])
    create unique_index(:revisions, [:work_id, :seq])
  end
end
