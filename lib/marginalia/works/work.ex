defmodule Marginalia.Works.Work do
  use Ecto.Schema
  import Ecto.Changeset

  schema "works" do
    # the URL carries this, not the id: a draft is unlisted rather than
    # numbered, so /works/3 is not a guess away from someone else's draft
    field :slug, :string
    field :title, :string
    field :intent, :string
    # where it was read from, when it came off the web rather than a keyboard
    field :source_url, :string
    # several drafts that are one thing — a case, a book, a series
    field :collection, :string
    field :collection_role, :string
    field :body, :string
    # the prose as it arrived, so the diff has a fixed point to measure from
    field :baseline_body, :string
    field :word_count, :integer, default: 0
    field :status, :string, default: "pending"
    field :status_detail, :string
    field :first_impression, :string

    belongs_to :user, Marginalia.Accounts.User
    # where the writer filed it; nil is the top of their tree. Moves go
    # through `Marginalia.Folders`, not through this changeset — filing a
    # draft must not have to satisfy the rules for writing one.
    belongs_to :folder, Marginalia.Folders.Folder
    has_many :sections, Marginalia.Works.Section, preload_order: [asc: :ordinal]
    has_many :nodes, Marginalia.Works.Node

    timestamps(type: :utc_datetime)
  end

  @statuses ~w(pending reading read failed)

  def changeset(work, attrs) do
    work
    |> cast(attrs, [
      :title,
      :intent,
      :body,
      :status,
      :status_detail,
      :first_impression,
      :source_url,
      :collection,
      :collection_role,
      :baseline_body
    ])
    |> put_slug()
    |> validate_required([:title, :body])
    |> validate_length(:title, max: 200)
    |> validate_inclusion(:status, @statuses)
    |> put_word_count()
    |> validate_number(:word_count, greater_than: 0, message: "looks empty")
  end

  # 128 bits, generated once and never regenerated — the link people have
  # must keep working.
  defp put_slug(changeset) do
    case get_field(changeset, :slug) do
      nil ->
        put_change(
          changeset,
          :slug,
          :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
        )

      _ ->
        changeset
    end
  end

  defp put_word_count(changeset) do
    case get_field(changeset, :body) do
      body when is_binary(body) ->
        put_change(changeset, :word_count, length(String.split(body, ~r/\s+/, trim: true)))

      _ ->
        changeset
    end
  end
end
