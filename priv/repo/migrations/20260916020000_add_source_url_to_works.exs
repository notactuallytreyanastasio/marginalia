defmodule Marginalia.Repo.Migrations.AddSourceUrlToWorks do
  use Ecto.Migration

  def change do
    # where a draft was read from, when it was not typed here
    alter table(:works) do
      add :source_url, :string
    end
  end
end
