defmodule Marginalia.Cuts.Cut do
  @moduledoc "A line drawn through several drafts, and what it turned out to say."
  use Ecto.Schema
  import Ecto.Changeset

  schema "cuts" do
    field :title, :string
    field :question, :string
    field :status, :string, default: "draft"
    field :status_detail, :string

    field :thesis, :string
    field :threads, {:array, :map}, default: []
    field :tensions, {:array, :map}, default: []
    field :not_supported, :string
    field :dropped, {:array, :string}, default: []
    field :content_sha, :string
    field :scope, :string, default: "folder"
    # [%{"n" => 1, "kind" => "work"|"folder", "id" => 12, "label" => "..."}]
    field :members, {:array, :map}, default: []

    belongs_to :user, Marginalia.Accounts.User
    belongs_to :folder, Marginalia.Folders.Folder

    timestamps(type: :utc_datetime)
  end

  @statuses ~w(draft reading read failed)

  def changeset(cut, attrs) do
    cut
    |> cast(attrs, [:title, :question, :folder_id, :status, :status_detail, :scope])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title])
    |> validate_length(:title, max: 200)
    |> validate_inclusion(:status, @statuses)
  end

  @doc "The result of a read, stored only with the fingerprint it was made from."
  def result_changeset(cut, attrs) do
    cut
    |> cast(attrs, [
      :thesis,
      :threads,
      :tensions,
      :not_supported,
      :dropped,
      :content_sha,
      :status,
      :members
    ])
    |> validate_inclusion(:status, @statuses)
  end
end
