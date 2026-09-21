defmodule Marginalia.Runs do
  @moduledoc """
  Long work that outlives the page that started it.

  `start_async/3` in a LiveView spawns a task linked to the socket's
  process. Close the tab, lose the wifi, walk into a lift — the socket goes,
  the process goes, and the task goes with it. For a form submission that is
  correct. For reading a hundred and forty-seven pull requests forwards,
  which is a hundred and forty-seven sequential model calls and the better
  part of two hours, it means the work is destroyed by a network blip and
  the money is already spent.

  So the work runs under `Marginalia.TaskSupervisor`, which belongs to the
  application and not to anybody's browser, and this module is the thing
  that remembers it is running.

  ## What it holds, and for how long

  One entry per key, in ETS: what kind of run it is, how far along, when it
  started. A page that mounts asks `get/1` and finds the run already in
  flight; a page that was open gets told over PubSub. Neither of them owns
  it.

  The entry lives as long as the node does and no longer. That is the
  honest boundary: this survives a dropped socket, a reload, a second tab
  and a different browser, and it does not survive a deploy. Making it
  survive a deploy means a job table and a worker that resumes mid-stack,
  which is a different piece of work — `Marginalia.Recovery` is what runs
  at boot to mark whatever was in flight as interrupted rather than leaving
  it looking alive.

  ## One run per key

  `start/3` refuses when the key already has something running, and says
  what. Two forward reads over one folder would write the same steps twice
  and bill for it twice, and the way that happens is not malice — it is a
  second tab, or a button pressed again because the first press was on a
  socket that had already gone.
  """

  use GenServer

  require Logger

  @table :marginalia_runs

  # ==========================================================================
  # the client side

  @doc "The PubSub topic a key's progress is announced on."
  def topic(key), do: "run:#{inspect(key)}"

  @doc "Hear about a key's runs: started, progress, done, crashed."
  def subscribe(key), do: Phoenix.PubSub.subscribe(Marginalia.PubSub, topic(key))

  @doc """
  What is running for this key, or nil.

  Read straight from ETS in the calling process, so a page mounting does not
  queue behind a hundred progress updates.
  """
  def get(key) do
    case :ets.lookup(@table, key) do
      [{^key, run}] -> run
      [] -> nil
    end
  end

  @doc "Is anything running for this key?"
  def running?(key), do: get(key) != nil

  @doc """
  Run `fun` in a task nothing on a socket owns.

  `kind` is what to call it on a page that finds it already going. Returns
  `{:ok, run}`, or `{:error, {:already_running, kind}}`.

  Whatever `fun` returns is broadcast as `{:run, :done, kind, result}`, so
  it should be small: the page reloads from the database anyway, and a
  return value of every step of a stack is a copy of the stack sent to
  every subscriber.
  """
  def start(key, kind, fun) when is_function(fun, 0) do
    GenServer.call(__MODULE__, {:start, key, kind, fun})
  end

  @doc """
  Report progress from inside a running `fun`.

  `fields` is merged into the entry — `done:`, `total:` and `stage:` are the
  ones pages render. Cast, not call: a worker should never block on the
  bookkeeping, and a progress update that arrives late or not at all costs
  a stale number on a page, not a lost run.
  """
  def progress(key, fields), do: GenServer.cast(__MODULE__, {:progress, key, Map.new(fields)})

  @doc "Stop tracking a key. The task, if any, is left alone."
  def forget(key), do: GenServer.call(__MODULE__, {:forget, key})

  # ==========================================================================
  # the server

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    # public and read-concurrent for the same reason Marginalia.Cache's table
    # is: a page asking "is something running" should be an ETS lookup in its
    # own process, not a message to this one
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:start, key, kind, fun}, _from, refs) do
    case get(key) do
      %{kind: running} ->
        {:reply, {:error, {:already_running, running}}, refs}

      nil ->
        task = Task.Supervisor.async_nolink(Marginalia.TaskSupervisor, fun)

        run = %{
          kind: kind,
          done: 0,
          total: nil,
          stage: nil,
          pid: task.pid,
          started_at: DateTime.utc_now()
        }

        :ets.insert(@table, {key, run})
        broadcast(key, {:run, :started, run})

        {:reply, {:ok, run}, Map.put(refs, task.ref, key)}
    end
  end

  def handle_call({:forget, key}, _from, refs) do
    :ets.delete(@table, key)
    {:reply, :ok, refs}
  end

  @impl true
  def handle_cast({:progress, key, fields}, refs) do
    case get(key) do
      nil ->
        {:noreply, refs}

      run ->
        run = Map.merge(run, fields)
        :ets.insert(@table, {key, run})
        broadcast(key, {:run, :progress, run})
        {:noreply, refs}
    end
  end

  # the task finished and handed back a value
  @impl true
  def handle_info({ref, result}, refs) when is_reference(ref) do
    # the DOWN that follows is about a task we have already dealt with
    Process.demonitor(ref, [:flush])

    case Map.pop(refs, ref) do
      {nil, refs} ->
        {:noreply, refs}

      {key, refs} ->
        kind = kind_of(key)
        :ets.delete(@table, key)
        broadcast(key, {:run, :done, kind, result})
        {:noreply, refs}
    end
  end

  # ...or died without handing back anything
  def handle_info({:DOWN, ref, :process, _pid, reason}, refs) do
    case Map.pop(refs, ref) do
      {nil, refs} ->
        {:noreply, refs}

      {key, refs} ->
        kind = kind_of(key)
        :ets.delete(@table, key)
        Logger.warning("marginalia: run #{inspect(key)} (#{kind}) died: #{inspect(reason)}")
        broadcast(key, {:run, :crashed, kind, reason})
        {:noreply, refs}
    end
  end

  def handle_info(_other, refs), do: {:noreply, refs}

  defp kind_of(key) do
    case get(key) do
      %{kind: kind} -> kind
      nil -> :unknown
    end
  end

  defp broadcast(key, msg), do: Phoenix.PubSub.broadcast(Marginalia.PubSub, topic(key), msg)
end
