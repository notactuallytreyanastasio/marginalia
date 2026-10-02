defmodule Marginalia.Alloy do
  @moduledoc """
  Runs SQL that Alloy built.

  Alloy, a Temper ORM, builds statements; it does not hold connections. The
  statements arrive from the generated `Temper.MarginaliaCore` as plain
  structs, the text with `$1`, `$2`, ... and each parameter with its kind,
  and run here through `Repo.query/3`. That keeps the connection pool,
  transactions and the test sandbox exactly as they were.

  Each parameter is decoded by its kind because Postgrex encodes parameters
  in binary by type: a `bigint` parameter has to be an integer, not the text
  of one.
  """

  alias Marginalia.Repo
  alias Temper.MarginaliaCore.{Param, Statement}

  @doc "Run a statement. Returns `{:ok, rows}`, each row a map keyed by column atom, or `{:error, error}`."
  def query(%Statement{text: text, params: params}, opts \\ []) do
    if opts[:savepoint] && Repo.in_transaction?(),
      do: savepoint(fn -> run(text, params) end),
      else: run(text, params)
  end

  @doc "Like `query/2`, raising on a database error."
  def query!(statement) do
    case query(statement) do
      {:ok, rows} -> rows
      {:error, error} -> raise error
    end
  end

  defp run(text, params) do
    case Repo.query(text, Enum.map(params, &decode/1)) do
      {:ok, %{columns: nil, num_rows: n}} ->
        {:ok, n}

      {:ok, %{columns: columns, rows: rows}} ->
        keys = Enum.map(columns, &String.to_atom/1)
        {:ok, Enum.map(rows, &Map.new(Enum.zip(keys, &1)))}

      {:error, error} ->
        {:error, error}
    end
  end

  # Postgres aborts the whole transaction on a failed statement, so a caller
  # that means to recover from one (an insert that may hit a unique index)
  # runs it inside a savepoint, as Ecto's `mode: :savepoint` did.
  defp savepoint(fun) do
    Repo.query!("SAVEPOINT alloy")

    case fun.() do
      {:ok, _} = ok ->
        Repo.query!("RELEASE SAVEPOINT alloy")
        ok

      {:error, _} = error ->
        Repo.query!("ROLLBACK TO SAVEPOINT alloy")
        error
    end
  end

  defp decode(%Param{kind: "text", text: text}), do: text
  defp decode(%Param{kind: "int", text: text}), do: String.to_integer(text)
  defp decode(%Param{kind: "bool", text: text}), do: text == "true"
  defp decode(%Param{kind: "float", text: text}), do: String.to_float(text)
  defp decode(%Param{kind: "date", text: text}), do: Date.from_iso8601!(text)
end
