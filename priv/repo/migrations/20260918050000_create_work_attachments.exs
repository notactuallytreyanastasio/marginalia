defmodule Marginalia.Repo.Migrations.CreateWorkAttachments do
  use Ecto.Migration

  def change do
    # A draft is prose. Some documents come with something else attached that
    # nobody wrote as prose but that a reader has to be shown: the diff a pull
    # request describes, the transcript a summary covers, the file a chapter
    # is about. Quoting from it is how a guide gets code samples that exist.
    create table(:work_attachments) do
      add :work_id, references(:works, on_delete: :delete_all), null: false
      add :name, :string, null: false
      # diff | text — how to find a quotable passage inside it
      add :kind, :string, null: false, default: "text"
      add :content, :text, null: false
      add :byte_size, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:work_attachments, [:work_id, :name])
  end
end
