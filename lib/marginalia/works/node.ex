defmodule Marginalia.Works.Node do
  @moduledoc """
  One observation about the manuscript.

  `quote` is load-bearing: it is a verbatim span from the writer's own draft.
  A node whose quote could not be matched against the source is discarded by
  `Marginalia.Analysis.Anchor` before it is ever stored, so anything in this
  table is anchored to something the writer actually wrote.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "nodes" do
    field :node_type, :string
    field :title, :string
    field :body, :string
    field :quote, :string
    field :ordinal, :integer, default: 0
    field :status, :string, default: "pending"
    field :narrative, :string

    belongs_to :work, Marginalia.Works.Work
    belongs_to :section, Marginalia.Works.Section

    timestamps(type: :utc_datetime)
  end

  # the deciduous decision-graph vocabulary, plus the reading-pass types the
  # first analysis produces
  @types ~w(goal decision option observation action outcome revisit
            beat spine thread note question)
  @statuses ~w(pending chosen rejected superseded completed)

  def types, do: @types

  def changeset(node, attrs) do
    node
    |> cast(attrs, [
      :work_id,
      :section_id,
      :node_type,
      :title,
      :body,
      :quote,
      :ordinal,
      :status,
      :narrative
    ])
    |> validate_required([:work_id, :node_type, :title])
    |> validate_inclusion(:node_type, @types)
    |> validate_inclusion(:status, @statuses)
  end
end
