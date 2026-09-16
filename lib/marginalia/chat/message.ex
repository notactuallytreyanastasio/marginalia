defmodule Marginalia.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  schema "messages" do
    field :role, :string
    field :content, :string
    belongs_to :conversation, Marginalia.Chat.Conversation
    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(m, attrs) do
    m
    |> cast(attrs, [:conversation_id, :role, :content])
    |> validate_required([:conversation_id, :role, :content])
    |> validate_inclusion(:role, ["user", "assistant"])
  end
end
