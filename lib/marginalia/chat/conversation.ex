defmodule Marginalia.Chat.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "conversations" do
    field :title, :string
    field :mode, :string, default: "read"

    # Where in the draft this thread lives. "work" is the old whole-draft
    # chat; "block" is a thread pinned to one paragraph; "span" is one pinned
    # to a passage the writer selected inside it.
    field :anchor_kind, :string, default: "work"
    field :block_ref, :string
    field :quote, :string
    field :resolved_at, :utc_datetime

    belongs_to :section, Marginalia.Works.Section
    belongs_to :work, Marginalia.Works.Work
    has_many :messages, Marginalia.Chat.Message
    timestamps(type: :utc_datetime)
  end

  def changeset(c, attrs) do
    c
    |> cast(attrs, [
      :work_id,
      :title,
      :mode,
      :anchor_kind,
      :section_id,
      :block_ref,
      :quote,
      :resolved_at
    ])
    |> validate_inclusion(:anchor_kind, ~w(work block span))
    |> validate_required([:work_id])
    |> validate_inclusion(:mode, Marginalia.Chat.Editor.mode_names())
  end
end
