defmodule Marginalia.Repo.Migrations.SummariesKnowTheirNeighbours do
  use Ecto.Migration

  @moduledoc """
  A section summary that knows where it sits.

  The first version reported one paragraph of prose from the section alone.
  Read that way every section re-establishes its own setup, because nothing
  told it the setup was three sections ago — which is the same failure
  `Stacks.read_step/6` avoids by handing each document what the ones before
  it established.
  """

  def change do
    alter table(:sections) do
      # the concrete things this section deals with, each verified to appear
      # in its text before it is kept
      add :summary_covers, {:array, :string}, default: []

      # ordinals this section leans on, and what it leaves for later
      add :summary_follows, {:array, :integer}, default: []
      add :summary_sets_up, :text

      # what was thrown away, and why — a summary is not quote-checkable but
      # its nouns are
      add :summary_dropped, {:array, :string}, default: []
    end
  end
end
