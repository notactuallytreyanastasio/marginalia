defmodule Marginalia.Repo.Migrations.CreateLinks do
  use Ecto.Migration

  def change do
    # A pairing of two manuscripts, and the run that related them.
    create table(:links) do
      add :a_work_id, references(:works, on_delete: :delete_all), null: false
      add :b_work_id, references(:works, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "pending"
      add :summary, :text
      add :error, :string

      timestamps(type: :utc_datetime)
    end

    # the pair is stored in a canonical order (lower id first) so this index
    # actually prevents the duplicate rather than only half of it
    create unique_index(:links, [:a_work_id, :b_work_id])
    create index(:links, [:b_work_id])
    create constraint(:links, :links_are_between_two_works, check: "a_work_id <> b_work_id")

    # Edges whose two ends are in different manuscripts.
    #
    # Deliberately not the `edges` table. That one carries a `work_id` and
    # every query over it is scoped by that column, so a cross-work edge
    # would either need a null there — quietly falling out of every existing
    # query — or a lie about which manuscript owns it. Neither owns it. It
    # belongs to the pair.
    #
    # The node foreign keys still cascade, so deleting either manuscript
    # takes its half of the links with it.
    create table(:link_edges) do
      add :link_id, references(:links, on_delete: :delete_all), null: false
      add :from_id, references(:nodes, on_delete: :delete_all), null: false
      add :to_id, references(:nodes, on_delete: :delete_all), null: false
      add :edge_type, :string, null: false
      add :rationale, :text
      add :ordinal, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:link_edges, [:link_id, :from_id, :to_id, :edge_type])
    create index(:link_edges, [:link_id, :ordinal])
    create index(:link_edges, [:from_id])
    create index(:link_edges, [:to_id])
  end
end
