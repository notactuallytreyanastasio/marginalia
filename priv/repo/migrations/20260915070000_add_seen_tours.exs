defmodule Marginalia.Repo.Migrations.AddSeenTours do
  use Ecto.Migration

  # Which tabs this person has already had explained. On the user row rather
  # than in localStorage so a guest who comes back on the same session is not
  # told twice, and so clearing a cache does not restart the tour.
  def change do
    alter table(:users) do
      add :seen_tours, {:array, :string}, null: false, default: []
    end
  end
end
