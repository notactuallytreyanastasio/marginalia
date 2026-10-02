defmodule Marginalia.Folders.Invalid do
  @moduledoc """
  Why a folder write was refused: `errors` maps a field to its messages, the
  shape `Ecto.Changeset.traverse_errors/2` gave, so callers that showed the
  first message still can.

  Two sources feed it: Alloy's changeset validations, run in Temper before
  any SQL, and the unique sibling-name indexes, which only Postgres can
  check.
  """

  defstruct errors: %{}

  @type t :: %__MODULE__{errors: %{atom() => [String.t()]}}

  @doc "The first message, for a flash."
  def first_message(%__MODULE__{errors: errors}) do
    errors |> Map.values() |> List.flatten() |> List.first()
  end
end
