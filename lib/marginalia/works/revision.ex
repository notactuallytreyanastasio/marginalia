defmodule Marginalia.Works.Revision do
  @moduledoc """
  One change to the draft's prose: the paragraph before, and after.

  A patch rather than a snapshot. Replaying every revision of a work in `seq`
  order over its `baseline_body` reproduces the current body, which is the
  property the diff view depends on and the one worth asserting in a test.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "revisions" do
    field :seq, :integer
    field :before, :string
    field :after, :string
    field :origin, :string, default: "edit"
    field :note, :string
    field :section_ordinal, :integer

    belongs_to :work, Marginalia.Works.Work
    belongs_to :section, Marginalia.Works.Section

    timestamps(type: :utc_datetime)
  end

  # `summary` is a whole body at once rather than a paragraph, from the brief
  # life of a control that replaced a draft with its own summary in place.
  # That was the wrong shape — the condensation should be a draft of its own,
  # so the two can be read against each other — and the control is gone. The
  # origin stays because a draft somewhere may have been through it, and a
  # history with a word the schema has since forgotten is a history that
  # cannot be loaded.
  @origins ~w(edit rewrite summary)
  def origins, do: @origins

  def changeset(rev, attrs) do
    rev
    |> cast(attrs, [
      :work_id,
      :section_id,
      :section_ordinal,
      :seq,
      :before,
      :after,
      :origin,
      :note
    ])
    |> validate_required([:work_id, :seq, :before, :after, :origin])
    |> validate_inclusion(:origin, @origins)
    |> unique_constraint([:work_id, :seq])
  end
end
