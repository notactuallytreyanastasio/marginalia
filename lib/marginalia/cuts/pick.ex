defmodule Marginalia.Cuts.Pick do
  @moduledoc "One passage, in one draft, that a cut passes through."
  use Ecto.Schema
  import Ecto.Changeset

  schema "cut_picks" do
    field :block_ref, :string
    field :quote, :string
    field :ordinal, :integer, default: 0

    belongs_to :cut, Marginalia.Cuts.Cut
    belongs_to :work, Marginalia.Works.Work

    timestamps(type: :utc_datetime)
  end

  def changeset(pick, attrs) do
    pick
    |> cast(attrs, [:cut_id, :work_id, :block_ref, :quote, :ordinal])
    |> validate_required([:work_id, :block_ref, :quote])
    |> unique_constraint([:cut_id, :work_id, :block_ref],
      message: "that passage is already in this cut"
    )
  end
end
