defmodule Marginalia.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :marginalia

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
  @doc """
  Grant admin to a user by email.

  Admin is only meaningful for one thing right now — choosing the model
  backend — and there is deliberately no self-serve path to it, so this runs
  from the release:

      bin/marginalia rpc 'Marginalia.Release.make_admin("you@example.com")'
  """
  def make_admin(email) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(Marginalia.Repo, fn _repo ->
      case Marginalia.Repo.get_by(Marginalia.Accounts.User, email: email) do
        nil ->
          IO.puts("no user with that email")

        user ->
          user |> Ecto.Changeset.change(is_admin: true) |> Marginalia.Repo.update!()
          IO.puts("#{email} is now an admin")
      end
    end)
  end
end
