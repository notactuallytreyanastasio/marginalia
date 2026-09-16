defmodule Marginalia.Works.Correction do
  @moduledoc """
  A thing the writer told the reader it had wrong, or had decided.

  Two kinds, and the difference matters:

  * `misread` — the reader got a fact about the manuscript wrong. It should
    never assert that again, because it is simply false.
  * `ruling` — the reader was not wrong, but the writer has decided. Their
    book. It may be raised again only when the same pattern appears somewhere
    new, and then only with the ruling acknowledged out loud.

  Repeating a note the writer has already overruled is the fastest way for
  this to feel like software instead of a reader, which is why it is stored
  rather than left to the context window.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "corrections" do
    field :kind, :string
    field :about, :string
    field :ruling, :string
    field :section_ordinal, :integer

    belongs_to :work, Marginalia.Works.Work
    timestamps(type: :utc_datetime)
  end

  @kinds ~w(misread ruling)
  def kinds, do: @kinds

  def changeset(c, attrs) do
    c
    |> cast(attrs, [:work_id, :kind, :about, :ruling, :section_ordinal])
    |> validate_required([:work_id, :kind, :about])
    |> validate_inclusion(:kind, @kinds)
    |> validate_length(:about, max: 1000)
    |> validate_length(:ruling, max: 1000)
  end
end
