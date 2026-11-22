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

  ## On a cluster

  There is one `Runs` server for the whole cluster, started by
  `Marginalia.Singleton` on whichever node wins, and the tasks run on that
  node. Every node has a `Runs.Mirror` that owns the ETS table pages read,
  and the server writes each change into every node's mirror before it
  announces anything, so a page that hears "done" never reads "running"
  afterwards. A node that joins copies the table from the server.

  The `fun` a page hands over is sent to the server's node and run there.
  That needs the same code on both ends: during a rolling deploy, a run
  started on a new node while the server is on an old one fails with
  `:badfun`, and says so, rather than doing something else.

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
  `{:ok, run}`, `{:error, {:already_running, kind}}`, or `{:error, :starting}`
  while no node is the server yet.

  Whatever `fun` returns is broadcast as `{:run, :done, kind, result}`, so
  it should be small: the page reloads from the database anyway, and a
  return value of every step of a stack is a copy of the stack sent to
  every subscriber.
  """
  def start(key, kind, fun) when is_function(fun, 0) do
    GenServer.call(server(), {:start, key, kind, fun})
  catch
    # no server yet: this node is still joining the cluster (Singleton), or
    # a takeover is under way. Seconds, not a crash on the page.
    :exit, {:noproc, _} -> {:error, :starting}
  end

  @doc "The cluster's one Runs server."
  def server, do: {:global, __MODULE__}

  @doc """
  Report progress from inside a running `fun`.

  `fields` is merged into the entry — `done:`, `total:` and `stage:` are the
  ones pages render. Cast, not call: a worker should never block on the
  bookkeeping, and a progress update that arrives late or not at all costs
  a stale number on a page, not a lost run.
  """
  def progress(key, fields), do: GenServer.cast(server(), {:progress, key, Map.new(fields)})

  @doc "Stop tracking a key. The task, if any, is left alone."
  def forget(key), do: GenServer.call(server(), {:forget, key})

  @doc "Every run in flight, from the server (what a joining node copies)."
  def all, do: GenServer.call(server(), :all)

  # ==========================================================================
  # the server

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: opts[:name] || server())

  # State: %{refs: task ref => key, runs: key => run}. The runs map is the
  # truth; the mirrors are copies of it for reading.
  @impl true
  def init(_opts) do
    # Becoming the server means whatever the previous one was running died
    # with it (its node went), or this is the first boot: either way rows
    # left saying "reading" have nothing behind them. A node that joins a
    # cluster with a live server never gets here, so a rolling restart no
    # longer marks other nodes' runs as interrupted.
    Marginalia.Recovery.sweep()
    mirror(:reset)
    {:ok, %{refs: %{}, runs: %{}}}
  end

  @impl true
  def handle_call({:start, key, kind, fun}, _from, state) do
    case state.runs[key] do
      %{kind: running} ->
        {:reply, {:error, {:already_running, running}}, state}

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

        mirror({:put, key, run})
        broadcast(key, {:run, :started, run})

        {:reply, {:ok, run},
         %{state | refs: Map.put(state.refs, task.ref, key), runs: Map.put(state.runs, key, run)}}
    end
  end

  def handle_call({:forget, key}, _from, state) do
    mirror({:delete, key})
    {:reply, :ok, %{state | runs: Map.delete(state.runs, key)}}
  end

  def handle_call(:all, _from, state), do: {:reply, state.runs, state}

  @impl true
  def handle_cast({:progress, key, fields}, state) do
    case state.runs[key] do
      nil ->
        {:noreply, state}

      run ->
        run = Map.merge(run, fields)
        mirror({:put, key, run})
        broadcast(key, {:run, :progress, run})
        {:noreply, %{state | runs: Map.put(state.runs, key, run)}}
    end
  end

  # the task finished and handed back a value
  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    # the DOWN that follows is about a task we have already dealt with
    Process.demonitor(ref, [:flush])

    case Map.pop(state.refs, ref) do
      {nil, _} ->
        {:noreply, state}

      {key, refs} ->
        {kind, state} = finish(key, %{state | refs: refs})
        broadcast(key, {:run, :done, kind, result})
        {:noreply, state}
    end
  end

  # ...or died without handing back anything
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Map.pop(state.refs, ref) do
      {nil, _} ->
        {:noreply, state}

      {key, refs} ->
        {kind, state} = finish(key, %{state | refs: refs})
        Logger.warning("marginalia: run #{inspect(key)} (#{kind}) died: #{inspect(reason)}")
        broadcast(key, {:run, :crashed, kind, reason})
        {:noreply, state}
    end
  end

  def handle_info(_other, state), do: {:noreply, state}

  defp finish(key, state) do
    kind = case state.runs[key] do
      %{kind: kind} -> kind
      nil -> :unknown
    end

    mirror({:delete, key})
    {kind, %{state | runs: Map.delete(state.runs, key)}}
  end

  # Into this node's table, then every other node's, before anyone is told:
  # a page that hears "done" must not then read "running" from its mirror.
  # A node that does not answer within a second is behind until it next
  # copies the table (Mirror does on every nodeup).
  defp mirror(op) do
    __MODULE__.Mirror.apply_op(op)
    if Node.list() != [], do: :erpc.multicall(Node.list(), __MODULE__.Mirror, :apply_op, [op], 1_000)
    :ok
  end

  defp broadcast(key, msg), do: Phoenix.PubSub.broadcast(Marginalia.PubSub, topic(key), msg)
end

defmodule Marginalia.Runs.Mirror do
  @moduledoc """
  This node's copy of what the cluster is running: the ETS table
  `Marginalia.Runs.get/1` reads. The Runs server writes into it (and into
  every other node's) with `apply_op/1`; on start and whenever a node
  joins, it copies the server's whole table, which covers a node that was
  away while things changed.
  """
  use GenServer

  @table :marginalia_runs

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc false
  def apply_op({:put, key, run}), do: guard(fn -> :ets.insert(@table, {key, run}) end)
  def apply_op({:delete, key}), do: guard(fn -> :ets.delete(@table, key) end)
  def apply_op(:reset), do: guard(fn -> :ets.delete_all_objects(@table) end)

  defp guard(fun) do
    if :ets.whereis(@table) != :undefined, do: fun.()
    :ok
  end

  @impl true
  def init(_opts) do
    # public and read-concurrent for the same reason Marginalia.Cache's table
    # is: a page asking "is something running" should be an ETS lookup in its
    # own process, not a message to any server
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    :net_kernel.monitor_nodes(true)
    {:ok, nil, {:continue, :copy}}
  end

  @impl true
  def handle_continue(:copy, state) do
    copy()
    {:noreply, state}
  end

  @impl true
  def handle_info({:nodeup, _node}, state) do
    copy()
    {:noreply, state}
  end

  def handle_info(_other, state), do: {:noreply, state}

  # No server yet (this node is booting and will be it, or a takeover is
  # under way): nothing to copy, and the new server resets every mirror.
  # The sync first: at nodeup the new node's name table has not caught up,
  # the leader looks absent, and a node rejoining mid-run came up without
  # the run in its mirror (seen in the three-node lab).
  defp copy do
    if Node.list() != [], do: :global.sync()

    if Marginalia.Singleton.whereis(Marginalia.Runs) do
      runs = Marginalia.Runs.all()
      :ets.delete_all_objects(@table)
      Enum.each(runs, fn {key, run} -> :ets.insert(@table, {key, run}) end)
    end
  catch
    :exit, _ -> :ok
  end
end
