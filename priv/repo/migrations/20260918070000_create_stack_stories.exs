defmodule Marginalia.Repo.Migrations.CreateStackStories do
  use Ecto.Migration

  def change do
    # The longform telling. Composed from the steps, not from the documents:
    # both passes have already distilled and checked those, and a composer
    # that went back to the source would be a third extraction rather than a
    # composition — free to introduce claims nothing had checked.
    create table(:stack_stories) do
      add :folder_id, references(:folders, on_delete: :delete_all), null: false

      add :title, :text
      add :opening, :text
      # [%{"heading","prose","steps":[n],"turn"}] — the story in parts
      add :movements, :map
      add :closing, :text

      # every step the composition failed to account for. A story that covers
      # four of ten steps has thrown the method away, quietly.
      add :uncovered, {:array, :integer}, default: []
      add :dropped, {:array, :string}, default: []
      add :fingerprint, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:stack_stories, [:folder_id])
  end
end
