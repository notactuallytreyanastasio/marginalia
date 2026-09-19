defmodule Marginalia.Stacks.Story do
  @moduledoc "The longform telling of a stack, composed from its steps."
  use Ecto.Schema
  import Ecto.Changeset

  schema "stack_stories" do
    field :title, :string
    field :opening, :string
    field :movements, {:array, :map}, default: []
    field :closing, :string
    field :uncovered, {:array, :integer}, default: []
    field :dropped, {:array, :string}, default: []
    field :fingerprint, :string

    belongs_to :folder, Marginalia.Folders.Folder

    timestamps(type: :utc_datetime)
  end

  def changeset(story, attrs) do
    story
    |> cast(attrs, [
      :folder_id,
      :title,
      :opening,
      :movements,
      :closing,
      :uncovered,
      :dropped,
      :fingerprint
    ])
    |> validate_required([:folder_id])
    |> unique_constraint(:folder_id)
  end

  @doc "Whether every step of the stack found a place in the telling."
  def complete?(%__MODULE__{uncovered: u}), do: u in [nil, []]
end
