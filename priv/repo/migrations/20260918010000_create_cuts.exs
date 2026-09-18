defmodule Marginalia.Repo.Migrations.CreateCuts do
  use Ecto.Migration

  def change do
    # A cut is a line drawn through several drafts at once: passages picked
    # out of each, kept together, and read as one thing. The reading of a
    # single draft already exists; this is the reading of what several of them
    # say when you put the paragraphs side by side.
    create table(:cuts) do
      add :title, :string, null: false
      add :question, :text
      add :status, :string, null: false, default: "draft"
      add :status_detail, :text

      # what the model came back with, validated before it landed here
      add :thesis, :text
      add :threads, :map
      add :tensions, :map
      add :not_supported, :text
      add :dropped, :map

      # the picks this analysis was made from. A cut whose passages change
      # has an analysis about something else, and must not show it.
      add :content_sha, :string

      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :folder_id, references(:folders, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:cuts, [:user_id])
    create index(:cuts, [:folder_id])

    create table(:cut_picks) do
      add :cut_id, references(:cuts, on_delete: :delete_all), null: false
      add :work_id, references(:works, on_delete: :delete_all), null: false

      # where in the draft: section ordinal and block index within it, plus
      # the text itself. The ref locates it; the text is what was picked, and
      # the two disagreeing is a fact worth surfacing rather than repairing.
      add :block_ref, :string, null: false
      add :quote, :text, null: false
      add :ordinal, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:cut_picks, [:cut_id])
    create index(:cut_picks, [:work_id])
    create unique_index(:cut_picks, [:cut_id, :work_id, :block_ref])
  end
end
