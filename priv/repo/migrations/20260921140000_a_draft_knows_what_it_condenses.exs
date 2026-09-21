defmodule Marginalia.Repo.Migrations.ADraftKnowsWhatItCondenses do
  use Ecto.Migration

  # A summary draft is made *from* another draft, and until now the only
  # record of that was a title ending "— in summary". Matching on a title is
  # fine until somebody renames it, which is the first thing anybody does to
  # a draft they intend to keep.
  #
  # Nilify rather than cascade: deleting the long version should not delete
  # the condensation somebody has since been editing. It becomes a draft that
  # no longer says where it came from, which is true.
  def change do
    alter table(:works) do
      add :derived_from_id, references(:works, on_delete: :nilify_all)
    end

    create index(:works, [:derived_from_id])
  end
end
