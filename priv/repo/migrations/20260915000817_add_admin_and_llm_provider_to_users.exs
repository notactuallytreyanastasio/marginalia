defmodule Marginalia.Repo.Migrations.AddAdminAndLlmProviderToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :is_admin, :boolean, null: false, default: false
      # Which model backend this user's reads and chats run against. Only an
      # admin may set it; for everyone else it stays null and the deploy's
      # configured default is used.
      add :llm_provider, :string
    end
  end
end
