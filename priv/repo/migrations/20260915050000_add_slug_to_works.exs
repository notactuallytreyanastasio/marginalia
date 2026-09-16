defmodule Marginalia.Repo.Migrations.AddSlugToWorks do
  use Ecto.Migration
  import Ecto.Query

  # Drafts were addressed by a sequential id, so /works/3 was a guess away
  # from /works/4. Every work now has an unguessable slug and that is what
  # the URL carries: secret unless you have the link.
  def up do
    alter table(:works) do
      add :slug, :string
    end

    flush()

    for {id} <- Marginalia.Repo.all(from w in "works", select: {w.id}) do
      slug = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)

      Marginalia.Repo.update_all(
        from(w in "works", where: w.id == ^id),
        set: [slug: slug]
      )
    end

    alter table(:works) do
      modify :slug, :string, null: false
    end

    create unique_index(:works, [:slug])
  end

  def down do
    drop index(:works, [:slug])

    alter table(:works) do
      remove :slug
    end
  end
end
