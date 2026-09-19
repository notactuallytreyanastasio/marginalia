defmodule Marginalia.Stacks.Step do
  @moduledoc "One document of a stack, read forwards."
  use Ecto.Schema
  import Ecto.Changeset

  schema "stack_steps" do
    field :ordinal, :integer
    field :capability, :string
    field :requires, {:array, :integer}, default: []
    field :lesson, :string
    field :pitfall, :string
    field :pitfall_quote, :string
    field :excerpts, {:array, :map}, default: []
    field :fingerprint, :string
    field :dropped, {:array, :string}, default: []

    belongs_to :folder, Marginalia.Folders.Folder
    belongs_to :work, Marginalia.Works.Work

    timestamps(type: :utc_datetime)
  end

  def changeset(step, attrs) do
    step
    |> cast(attrs, [
      :folder_id,
      :work_id,
      :ordinal,
      :capability,
      :requires,
      :lesson,
      :pitfall,
      :pitfall_quote,
      :excerpts,
      :fingerprint,
      :dropped
    ])
    |> validate_required([:folder_id, :work_id, :ordinal])
    |> unique_constraint([:folder_id, :work_id])
  end
end
