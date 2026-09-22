defmodule Marginalia.Repo.Migrations.CreateMutterings do
  use Ecto.Migration

  def change do
    # A line to show in front of the three dots while a model is thinking.
    # Written by a model too, a cheap one, in character; seeded to a hundred
    # on boot and topped up on a timer. A table rather than a list in code,
    # because the point is that the supply keeps growing without a deploy.
    create table(:mutterings) do
      add :text, :text, null: false
      # "seed" for the first hundred, "cron" for every top-up after
      add :source, :string, null: false, default: "cron"

      timestamps(type: :utc_datetime)
    end
  end
end
