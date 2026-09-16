defmodule Marginalia.Repo.Migrations.AddGuestToUsers do
  use Ecto.Migration

  # Uploading no longer requires signing up. A visitor still gets a real user
  # row — created automatically and tied to their session — so every ownership
  # check downstream keeps working and one guest cannot see another's drafts.
  # The flag is what lets us tell them apart later, for cleanup and for the
  # "keep this" prompt.
  def change do
    alter table(:users) do
      add :is_guest, :boolean, null: false, default: false
    end

    create index(:users, [:is_guest])
  end
end
