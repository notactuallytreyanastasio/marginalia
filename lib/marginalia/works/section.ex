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
    # the section text this summary was written from, so a stale one can
    # show what moved under it rather than only saying that something did
    field :summary_body, :string
    field :summarised_at, :utc_datetime
    field :summary_covers, {:array, :string}, default: []
    field :summary_follows, {:array, :integer}, default: []
    field :summary_sets_up, :string
    field :summary_dropped, {:array, :string}, default: []

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
