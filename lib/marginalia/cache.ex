defmodule Marginalia.Cache do
  @moduledoc """
  Answers that are the same for every visitor, held in ETS.

  `Links.public_links/0` measured 64ms on 392 pairs, and 63ms of that is one
  query loading every link with both its works preloaded. It is the same
  answer for every visitor and it changes only when somebody links two drafts
  or a pass finishes, so paying for it per page view is paying for it for no
  reason.

  ## Read from the caller, not through the server

  The table is `:public` with `read_concurrency`, so a read is an ETS lookup
  in the process that wants it and never a message to this GenServer. The
  server exists to own the table — so it survives the process that happened
  to fill it — and to hold nothing else.

  ## Invalidated, and also expiring

  Every write path that can change the answer calls `invalidate/0`. That is
  the mechanism; the TTL underneath it is the admission that a mechanism like
  that is one forgotten call away from serving last week's list forever. A
  missed invalidation costs staleness until the entry expires rather than
  until somebody restarts the release.
  """
  use GenServer

  require Logger

  @table :marginalia_cache
  @ttl_ms :timer.minutes(5)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    {:ok, %{}}
  end

  @doc """
  The cached list, computing it if there is nothing fresh.

  `fun` is the expensive thing. It is passed in rather than called by name so
  that this module knows nothing about what it is caching, which is what
  keeps it testable without a database.
  """
  def fetch(key, fun, ttl \\ @ttl_ms) when is_function(fun, 0) do
    now = System.monotonic_time(:millisecond)

    case lookup(key, now, ttl) do
      {:ok, rows} ->
        rows

      :miss ->
        rows = fun.()
        put(key, rows, now)
        rows
    end
  end

  @doc "What is cached right now, without computing anything."
  def peek(key, ttl \\ @ttl_ms) do
    case lookup(key, System.monotonic_time(:millisecond), ttl) do
      {:ok, rows} -> {:ok, rows}
      :miss -> :miss
    end
  end

  @doc "Throw it away. Called from every path that can change the answer."
  def invalidate(key) do
    if :ets.whereis(@table) != :undefined, do: :ets.delete(@table, key)
    :ok
  end

  @doc "Throw all of it away."
  def invalidate_all do
    if :ets.whereis(@table) != :undefined, do: :ets.delete_all_objects(@table)
    :ok
  end

  defp lookup(key, now, ttl) do
    with false <- :ets.whereis(@table) == :undefined,
         [{^key, rows, at}] <- :ets.lookup(@table, key),
         true <- now - at < ttl do
      {:ok, rows}
    else
      _ -> :miss
    end
  end

  defp put(key, rows, now) do
    if :ets.whereis(@table) != :undefined, do: :ets.insert(@table, {key, rows, now})
    :ok
  rescue
    ArgumentError -> :ok
  end
end
