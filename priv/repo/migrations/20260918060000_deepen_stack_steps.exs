defmodule Marginalia.Repo.Migrations.DeepenStackSteps do
  use Ecto.Migration

  def change do
    # The forward pass is told only what came before each document, which is
    # the reading a learner can follow — and it means nothing it says can
    # account for what a later document changes. A second pass, holding the
    # whole chain, knows the future of every step. These are the fields only
    # that pass can fill.
    alter table(:stack_steps) do
      # how it actually works, below the level of "what to do"
      add :mechanism, :text
      # what to get right here because something later leans on it
      add :watch_for, :text
      # a later step that revises or corrects this one, and the sentence saying so
      add :revised_by, :integer
      add :revision, :text
      add :revision_quote, :text
      add :deep_dropped, {:array, :string}, default: []
      add :deepened_at, :utc_datetime
    end
  end
end
