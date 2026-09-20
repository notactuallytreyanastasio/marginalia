defmodule Marginalia.Works.DocumentSummary do
  @moduledoc "What the whole draft does, and the rules it is working under."
  use Ecto.Schema
  import Ecto.Changeset

  schema "document_summaries" do
    field :summary, :string
    field :throughline, :string
    field :movements, {:array, :map}, default: []
    field :guidelines, {:array, :map}, default: []
    field :tensions, {:array, :map}, default: []
    field :fingerprint, :string
    field :dropped, {:array, :string}, default: []

    belongs_to :work, Marginalia.Works.Work
    timestamps(type: :utc_datetime)
  end

  def changeset(d, attrs) do
    d
    |> cast(attrs, [
      :work_id,
      :summary,
      :throughline,
      :movements,
      :guidelines,
      :tensions,
      :fingerprint,
      :dropped
    ])
    |> validate_required([:work_id])
    |> unique_constraint(:work_id)
  end
end
