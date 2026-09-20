defmodule Marginalia.Works.Section do
  use Ecto.Schema
  import Ecto.Changeset

  schema "sections" do
    field :ordinal, :integer
    field :title, :string
    field :body, :string
    field :word_count, :integer, default: 0
    # what this section says, cached against the text it was made from
    field :summary, :string
    field :summary_fingerprint, :string
    field :summarised_at, :utc_datetime

    field :status, :string, default: "pending"

    belongs_to :work, Marginalia.Works.Work
    has_many :nodes, Marginalia.Works.Node

    timestamps(type: :utc_datetime)
  end

  def changeset(section, attrs) do
    section
    |> cast(attrs, [:ordinal, :title, :body, :status, :word_count])
    |> validate_required([:ordinal, :title, :body])
  end
end
