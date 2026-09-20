defmodule Marginalia.Folders.Folder do
  @moduledoc "A bucket of drafts, which may sit inside another bucket."
  use Ecto.Schema
  import Ecto.Changeset

  schema "folders" do
    field :name, :string

    # nil means private, which is every folder until somebody says otherwise
    field :published_at, :utc_datetime
    field :slug, :string

    belongs_to :user, Marginalia.Accounts.User
    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :works, Marginalia.Works.Work

    timestamps(type: :utc_datetime)
  end

  def changeset(folder, attrs) do
    folder
    |> cast(attrs, [:name, :parent_id])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 80)
    |> unique_constraint(:name,
      name: :folders_sibling_name_index,
      message: "there is already a folder with that name here"
    )
    |> unique_constraint(:name,
      name: :folders_root_name_index,
      message: "there is already a folder with that name here"
    )
  end
end
