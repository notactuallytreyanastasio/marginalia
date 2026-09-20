defmodule Marginalia.Repo.Migrations.FoldersCanBePublished do
  use Ecto.Migration

  @moduledoc """
  A stack that can be read by somebody without an account.

  Both columns are nullable and both default to nothing, which is the point:
  a folder is private until somebody says otherwise, and the same writer's
  contracts and employment agreements sit in folders beside the one being
  published. Publishing by accident has to be impossible, so it takes an
  explicit act and a slug that has to be minted.
  """

  def change do
    alter table(:folders) do
      # nil means private. The timestamp rather than a boolean because when
      # something was published is the question actually asked of it later.
      add :published_at, :utc_datetime
      add :slug, :string
    end

    create unique_index(:folders, [:slug])
    create index(:folders, [:published_at])
  end
end
