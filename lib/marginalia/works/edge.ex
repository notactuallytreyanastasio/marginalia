defmodule Marginalia.Works.Edge do
  use Ecto.Schema
  import Ecto.Changeset

  schema "edges" do
    field :edge_type, :string, default: "leads_to"
    field :ordinal, :integer, default: 0
    field :rationale, :string

    belongs_to :work, Marginalia.Works.Work
    belongs_to :from, Marginalia.Works.Node, foreign_key: :from_id
    belongs_to :to, Marginalia.Works.Node, foreign_key: :to_id

    timestamps(type: :utc_datetime)
  end

  def changeset(edge, attrs) do
    edge
    |> cast(attrs, [:work_id, :from_id, :to_id, :edge_type, :ordinal, :rationale])
    |> validate_required([:work_id, :from_id, :to_id, :edge_type])
  end
end
