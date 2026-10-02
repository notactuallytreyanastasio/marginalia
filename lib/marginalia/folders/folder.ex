defmodule Marginalia.Folders.Folder do
  @moduledoc """
  A bucket of drafts, which may sit inside another bucket.

  A plain struct. Its rows are read and written with SQL that Alloy builds
  (`temper/marginalia-core/src/folders.temper.md`), so there is no Ecto
  schema here. The fields are the ones the schema had. Timestamps come back
  from Postgres as naive UTC and are made `DateTime`s, as Ecto's
  `:utc_datetime` did.
  """

  defstruct [:id, :name, :published_at, :slug, :user_id, :parent_id, :inserted_at, :updated_at]

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          published_at: DateTime.t() | nil,
          slug: String.t() | nil,
          user_id: integer() | nil,
          parent_id: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc "A folder from a row `Marginalia.Alloy` returned."
  def from_row(row) do
    %__MODULE__{
      id: row.id,
      name: row.name,
      published_at: utc(row.published_at),
      slug: row.slug,
      user_id: row.user_id,
      parent_id: row.parent_id,
      inserted_at: utc(row.inserted_at),
      updated_at: utc(row.updated_at)
    }
  end

  defp utc(nil), do: nil
  defp utc(%NaiveDateTime{} = naive), do: DateTime.from_naive!(naive, "Etc/UTC")
end
