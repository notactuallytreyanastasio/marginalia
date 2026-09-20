defmodule Marginalia.Repo.Migrations.SummariseSections do
  use Ecto.Migration

  @moduledoc """
  A summary per section, cached against the text it was made from.

  The fingerprint is the point. A summary of a paragraph that has since been
  rewritten is worse than no summary — it is a confident description of prose
  that is not there any more — so what it was made from is stored beside it
  and the page can say "stale" instead of lying.
  """

  def change do
    alter table(:sections) do
      add :summary, :text
      add :summary_fingerprint, :string
      add :summarised_at, :utc_datetime
    end
  end
end
