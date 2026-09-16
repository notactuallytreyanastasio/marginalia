defmodule Marginalia.Repo.Migrations.AnchorConversations do
  use Ecto.Migration

  # A conversation can now be about one place in the draft rather than about
  # the draft in general. That is the difference between a chat panel and a
  # margin you can argue in: the thread lives next to the paragraph it is
  # about, and is still there when you come back to that paragraph.
  def change do
    alter table(:conversations) do
      add :anchor_kind, :string, null: false, default: "work"
      add :section_id, references(:sections, on_delete: :delete_all)
      add :block_ref, :string
      add :quote, :text
      add :resolved_at, :utc_datetime
    end

    create index(:conversations, [:work_id, :anchor_kind])
    create index(:conversations, [:section_id])
    # one thread per place, so clicking the same paragraph twice returns to
    # the conversation already there rather than starting a second one
    create unique_index(:conversations, [:work_id, :block_ref],
             where: "block_ref IS NOT NULL",
             name: :conversations_work_block_index
           )
  end
end
