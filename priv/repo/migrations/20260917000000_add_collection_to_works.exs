defmodule Marginalia.Repo.Migrations.AddCollectionToWorks do
  use Ecto.Migration

  def change do
    # Several drafts that belong to one thing: the opinion, the dissent and
    # the argument in a single case. Grouping on a title prefix would have
    # worked for the documents we ingest and broken on anything typed by
    # hand, so the grouping is a field.
    alter table(:works) do
      add :collection, :string
      add :collection_role, :string
    end

    create index(:works, [:collection])
  end
end
