defmodule Marginalia.Links.LinkEdge do
  @moduledoc """
  One relation between a node in one manuscript and a node in another.

  Same vocabulary as the edges inside a single draft, on purpose: a writer
  who has learned what `pays_off` means on one page should not have to learn
  a second set of words to read two.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "link_edges" do
    field :edge_type, :string
    field :rationale, :string
    field :ordinal, :integer, default: 0

    belongs_to :link, Marginalia.Links.Link
    belongs_to :from, Marginalia.Works.Node, foreign_key: :from_id
    belongs_to :to, Marginalia.Works.Node, foreign_key: :to_id

    timestamps(type: :utc_datetime)
  end

  def changeset(edge, attrs) do
    edge
    |> cast(attrs, [:link_id, :from_id, :to_id, :edge_type, :rationale, :ordinal])
    |> validate_required([:link_id, :from_id, :to_id, :edge_type])
    |> unique_constraint([:link_id, :from_id, :to_id, :edge_type])
  end
end
