defmodule Marginalia.Works.Attachment do
  @moduledoc "Something a draft carries besides its prose, that can be quoted from."
  use Ecto.Schema
  import Ecto.Changeset

  schema "work_attachments" do
    field :name, :string
    field :kind, :string, default: "text"
    field :content, :string
    field :byte_size, :integer, default: 0

    belongs_to :work, Marginalia.Works.Work

    timestamps(type: :utc_datetime)
  end

  @kinds ~w(diff text)

  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [:work_id, :name, :kind, :content])
    |> validate_required([:work_id, :name, :content])
    |> put_kind()
    |> validate_inclusion(:kind, @kinds)
    |> put_size()
    |> unique_constraint([:work_id, :name])
  end

  # Detected rather than declared: a caller who has just fetched a patch
  # should not also have to remember to say so, and the content is the
  # authority on what it is.
  defp put_kind(changeset) do
    case get_field(changeset, :kind) do
      k when k in @kinds and not is_nil(k) ->
        content = get_field(changeset, :content) || ""
        name = get_field(changeset, :name) || ""

        cond do
          k != "text" -> changeset
          String.starts_with?(String.trim_leading(content), "diff --git") -> put_change(changeset, :kind, "diff")
          String.ends_with?(name, ".patch") or String.ends_with?(name, ".diff") -> put_change(changeset, :kind, "diff")
          true -> changeset
        end

      _ ->
        changeset
    end
  end

  defp put_size(changeset) do
    put_change(changeset, :byte_size, byte_size(get_field(changeset, :content) || ""))
  end
end
