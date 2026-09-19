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

    # filled by the second pass, which can see the whole chain
    field :mechanism, :string
    field :watch_for, :string
    field :revised_by, :integer
    field :revision, :string
    field :revision_quote, :string
    field :deep_dropped, {:array, :string}, default: []
    field :deepened_at, :utc_datetime

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
  end

  @doc "What only a pass holding the whole chain can say."
  def deep_changeset(step, attrs) do
    step
    |> cast(attrs, [
      :mechanism,
      :watch_for,
      :revised_by,
      :revision,
      :revision_quote,
      :deep_dropped,
      :deepened_at
    ])
    |> validate_required([:folder_id, :work_id, :ordinal])
    |> unique_constraint([:folder_id, :work_id])
  end
end
