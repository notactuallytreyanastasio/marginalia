defmodule Marginalia.Repo.Migrations.AddModeToConversations do
  use Ecto.Migration

  def change do
    alter table(:conversations) do
      # read | provoke | bounce — which kind of conversation this is. Kept on
      # the conversation rather than passed per message so reopening one
      # resumes the stance it was held in.
      add :mode, :string, null: false, default: "read"
    end
  end
end
