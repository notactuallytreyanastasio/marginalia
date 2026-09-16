defmodule Marginalia.Links.Link do
  @moduledoc """
  Two manuscripts, and the relationship drawn between their graphs.

  The pair is unordered — "these two are related" is symmetric — so it is
  stored with the lower work id first and the unique index does the rest.
  Individual edges inside it are directed, which is where the asymmetry
  actually lives.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "links" do
    field :status, :string, default: "pending"
    field :summary, :string
    field :error, :string

    belongs_to :a_work, Marginalia.Works.Work, foreign_key: :a_work_id
    belongs_to :b_work, Marginalia.Works.Work, foreign_key: :b_work_id
    has_many :edges, Marginalia.Links.LinkEdge

    timestamps(type: :utc_datetime)
  end

  def changeset(link, attrs) do
    link
    |> cast(attrs, [:a_work_id, :b_work_id, :status, :summary, :error])
    |> validate_required([:a_work_id, :b_work_id])
    |> validate_inclusion(:status, ~w(pending linking linked failed))
    |> check_constraint(:a_work_id, name: :links_are_between_two_works)
    |> unique_constraint([:a_work_id, :b_work_id])
  end
end
