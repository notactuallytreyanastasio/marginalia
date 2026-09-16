defmodule Marginalia.Repo.Migrations.CreateGraphEvents do
  use Ecto.Migration

  # Every tool call the model makes while building a decision graph, and what
  # the server answered. The refusals are the interesting half: they are the
  # record of the flow rule and the anchoring guarantee actually firing.
  def change do
    create table(:graph_events) do
      add :work_id, references(:works, on_delete: :delete_all), null: false
      add :narrative, :string
      add :seq, :integer, null: false, default: 0
      add :tool, :string, null: false
      add :args, :text
      add :result, :text
      add :ok, :boolean, null: false, default: true
      add :node_id, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:graph_events, [:work_id, :seq])
  end
end
