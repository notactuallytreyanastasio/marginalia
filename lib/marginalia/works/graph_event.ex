defmodule Marginalia.Works.GraphEvent do
  @moduledoc """
  One tool call made while building a decision graph, and the server's answer.

  This exists because the interesting question about an automated
  `/decision-graph` run is not only what graph came out — it is what the model
  *tried*. A refused link is the flow rule doing its job; a refused quote is
  the anchoring guarantee doing its job. Without this table both are invisible
  and the whole pipeline has to be taken on faith.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "graph_events" do
    field :narrative, :string
    field :seq, :integer, default: 0
    field :tool, :string
    field :args, :string
    field :result, :string
    field :ok, :boolean, default: true
    field :node_id, :integer

    belongs_to :work, Marginalia.Works.Work

    timestamps(type: :utc_datetime)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:work_id, :narrative, :seq, :tool, :args, :result, :ok, :node_id])
    |> validate_required([:work_id, :tool])
  end
end
