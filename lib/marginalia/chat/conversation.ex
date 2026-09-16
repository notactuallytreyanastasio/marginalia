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
    # a conversation about how two drafts relate belongs to the link
    belongs_to :link, Marginalia.Links.Link
    has_many :messages, Marginalia.Chat.Message
    timestamps(type: :utc_datetime)
  end

  def changeset(c, attrs) do
    c
    |> cast(attrs, [
      :work_id,
      :link_id,
      :title,
      :mode,
      :anchor_kind,
      :section_id,
      :block_ref,
      :quote,
      :resolved_at
    ])
    |> validate_inclusion(:anchor_kind, ~w(work block span link))
    |> one_home()
    |> validate_inclusion(:mode, Marginalia.Chat.Editor.mode_names())
    |> check_constraint(:work_id, name: :conversation_belongs_somewhere)
  end

  # exactly one of the two, which the database also enforces
  defp one_home(changeset) do
    work = get_field(changeset, :work_id)
    link = get_field(changeset, :link_id)

    cond do
      is_nil(work) and is_nil(link) ->
        add_error(changeset, :work_id, "a conversation belongs to a draft or to a link")

      work && link ->
        add_error(changeset, :work_id, "a conversation belongs to one or the other, not both")

      true ->
        changeset
    end
  end
end
