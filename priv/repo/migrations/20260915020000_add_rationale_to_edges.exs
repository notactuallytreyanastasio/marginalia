defmodule Marginalia.Repo.Migrations.AddRationaleToEdges do
  use Ecto.Migration

  # The model gives a reason for every link it draws — "the stated prerequisite
  # needs a demonstration to land" — and we were dropping it on the floor. It
  # is the commentary that makes a graph readable rather than a shape.
  def change do
    alter table(:edges) do
      add :rationale, :text
    end
  end
end
