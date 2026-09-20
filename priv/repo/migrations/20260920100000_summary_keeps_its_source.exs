defmodule Marginalia.Repo.Migrations.SummaryKeepsItsSource do
  use Ecto.Migration

  @moduledoc """
  The text a summary was written from, kept beside it.

  The fingerprint could say a summary had gone stale but not what had
  changed under it, which is the thing a writer needs to decide whether it
  is worth running again. A hash cannot be diffed; the prose can.
  """

  def change do
    alter table(:sections) do
      add :summary_body, :text
    end
  end
end
