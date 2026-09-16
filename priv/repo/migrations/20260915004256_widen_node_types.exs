defmodule Marginalia.Repo.Migrations.WidenNodeTypes do
  use Ecto.Migration

  def change do
    # The graph is built with the deciduous decision-graph vocabulary now
    # (goal / decision / option / observation / action / outcome / revisit),
    # so nodes carry those types natively rather than being translated at
    # export time. `status` lets an option be marked chosen or rejected, which
    # is how the methodology records a decision that was actually taken.
    alter table(:nodes) do
      add :status, :string, null: false, default: "pending"
      # which narrative/thread this node belongs to — the skill's unit of
      # story before any graph is drawn
      add :narrative, :string
    end

    create index(:nodes, [:work_id, :narrative])
  end
end
