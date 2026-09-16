defmodule Marginalia.Repo.Migrations.CreateWorks do
  use Ecto.Migration

  def change do
    # A work is one manuscript a writer uploaded: a novel, an essay, a post.
    create table(:works) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :title, :string, null: false
      # "what is this supposed to do to a reader?" — the writer's own stated
      # intent, which every note is written against
      add :intent, :text
      add :body, :text, null: false
      add :word_count, :integer, null: false, default: 0
      # pending | reading | read | failed
      add :status, :string, null: false, default: "pending"
      add :status_detail, :string
      # the model's first impression of the whole work, written once The Read lands
      add :first_impression, :text

      timestamps(type: :utc_datetime)
    end

    create index(:works, [:user_id, :id])

    # The writer-confirmed division of the manuscript. All analysis is per
    # section, so this is the unit of work for the whole pipeline.
    create table(:sections) do
      add :work_id, references(:works, on_delete: :delete_all), null: false
      add :ordinal, :integer, null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :word_count, :integer, null: false, default: 0
      # pending | reading | read | failed
      add :status, :string, null: false, default: "pending"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:sections, [:work_id, :ordinal])

    # The map itself. One table for every kind of observation so the explorer
    # and the chat tools have a single shape to work with.
    create table(:nodes) do
      add :work_id, references(:works, on_delete: :delete_all), null: false
      add :section_id, references(:sections, on_delete: :delete_all)
      # beat | spine | thread | note | question
      add :node_type, :string, null: false
      add :title, :text, null: false
      add :body, :text
      # the verbatim sentence from the writer's own draft that licenses this
      # node. A node that could not be anchored is discarded, never shown.
      add :quote, :text
      add :ordinal, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:nodes, [:work_id, :node_type, :ordinal])
    create index(:nodes, [:section_id])

    # Edges carry an explicit ordinal: the lane-tree renderer picks each node's
    # trunk parent by lowest edge id, so without a deterministic order a
    # parallel pipeline draws a different shape on every run.
    create table(:edges) do
      add :work_id, references(:works, on_delete: :delete_all), null: false
      add :from_id, references(:nodes, on_delete: :delete_all), null: false
      add :to_id, references(:nodes, on_delete: :delete_all), null: false
      add :edge_type, :string, null: false, default: "leads_to"
      add :ordinal, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:edges, [:work_id, :ordinal])
    create unique_index(:edges, [:from_id, :to_id, :edge_type])

    create table(:conversations) do
      add :work_id, references(:works, on_delete: :delete_all), null: false
      add :title, :string
      timestamps(type: :utc_datetime)
    end

    create index(:conversations, [:work_id, :id])

    create table(:messages) do
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :content, :text, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:messages, [:conversation_id, :id])
  end
end
