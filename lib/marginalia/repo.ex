defmodule Marginalia.Repo do
  use Ecto.Repo,
    otp_app: :marginalia,
    adapter: Ecto.Adapters.Postgres
end
