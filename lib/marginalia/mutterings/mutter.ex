defmodule Marginalia.Mutterings.Mutter do
  @moduledoc "One line said at the sandwich counter. See `Marginalia.Mutterings`."
  use Ecto.Schema

  schema "mutterings" do
    field :text, :string
    field :source, :string, default: "cron"

    timestamps(type: :utc_datetime)
  end
end
