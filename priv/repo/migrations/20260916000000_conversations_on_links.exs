defmodule Marginalia.Repo.Migrations.ConversationsOnLinks do
  use Ecto.Migration

  def change do
    # A conversation about the relationship between two drafts belongs to the
    # link, not to either of them. `work_id` becomes optional for exactly
    # that case; every other conversation still has one.
    alter table(:conversations) do
      add :link_id, references(:links, on_delete: :delete_all)
    end

    execute "ALTER TABLE conversations ALTER COLUMN work_id DROP NOT NULL",
            "ALTER TABLE conversations ALTER COLUMN work_id SET NOT NULL"

    create index(:conversations, [:link_id])

    create constraint(:conversations, :conversation_belongs_somewhere,
             check: "(work_id IS NOT NULL) <> (link_id IS NOT NULL)"
           )
  end
end
