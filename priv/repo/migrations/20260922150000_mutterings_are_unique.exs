defmodule Marginalia.Repo.Migrations.MutteringsAreUnique do
  use Ecto.Migration

  def up do
    # The model repeats itself across calls, and a line stored twice is a
    # line shown twice as often. Duplicates already there go first, keeping
    # the earliest, then the index refuses the next one.
    execute """
    DELETE FROM mutterings a USING mutterings b
    WHERE a.text = b.text AND a.id > b.id
    """

    create unique_index(:mutterings, [:text])
  end

  def down do
    drop unique_index(:mutterings, [:text])
  end
end
