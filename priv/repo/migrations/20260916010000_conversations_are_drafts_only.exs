defmodule Marginalia.Repo.Migrations.ConversationsAreDraftsOnly do
  use Ecto.Migration

  @moduledoc """
  The chat about a linked pair is not kept, so it has no row to live in.

  A conversation about two drafts' graph is about a shape that changes
  every time either draft is re-read or the pair is linked again. Resuming
  one would mean answering from turns that were about a graph which no
  longer exists. Those turns now live in the LiveView and die with it.
  """

  def up do
    # any that were made while the chat did persist
    execute "DELETE FROM conversations WHERE link_id IS NOT NULL"

    drop constraint(:conversations, :conversation_belongs_somewhere)

    alter table(:conversations) do
      remove :link_id
    end

    execute "ALTER TABLE conversations ALTER COLUMN work_id SET NOT NULL"
  end

  def down do
    alter table(:conversations) do
      add :link_id, references(:links, on_delete: :delete_all)
    end

    execute "ALTER TABLE conversations ALTER COLUMN work_id DROP NOT NULL"
    create index(:conversations, [:link_id])

    create constraint(:conversations, :conversation_belongs_somewhere,
             check: "(work_id IS NOT NULL) <> (link_id IS NOT NULL)"
           )
  end
end
