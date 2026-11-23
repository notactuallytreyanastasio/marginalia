defmodule Marginalia.Singleton do
  @moduledoc """
  One of something for the whole cluster, whichever node it lands on.

  Every node runs one of these per name. To lead, a node must first hold a
  Postgres advisory lock for the name, on a connection of its own; only
  then does it start the real process under a `:global` name, linked to
  this process. Every other node is a follower: it monitors the leader
  and, when it goes, waits a moment and tries for the lock again.

  Why not just start the process on every node: `Marginalia.Runs` exists
  to say "one run per key", and three nodes each holding their own table
  would each say yes. `Marginalia.Mutterings.Clock` asks a model for lines
  every half hour; three of them ask three times.

  ## Why the lock, and not `:global` alone

  `:global` decides by who can see whom, and during a network split each
  side sees no leader and elects its own. That was measured on a three-node
  cluster in the lab: the node cut off from the other two elected its own
  `Runs`, and as OTP's partition protection kept disconnecting and
  reconnecting it, `:global` resolved 128 name conflicts in 3 minutes, a
  new election every 3 s. Each election ran `Runs`' boot sweep, which marks
  every running run failed, so the isolated node kept failing runs that
  were alive on the real leader.

  Every node talks to the same Postgres, so the database is a referee that
  does not split with the network. A session advisory lock has exactly one
  holder; it is released when the holder's session ends, whether the
  holder stopped, crashed, or lost the database. An isolated node finds
  the lock taken, leads nothing, and retries until the split heals or the
  holder's session goes. Because only the lock holder ever registers the
  global name, `:global` never sees two of them.

  The cost: while the leader is cut off from the other nodes but not from
  Postgres, it keeps leading, and the nodes that cannot reach it have no
  leader (`Marginalia.Runs` answers `{:error, :starting}` there). No leader
  on one side is the trade made on purpose; two leaders is what failed runs.

  The lock's connection does not reconnect (`backoff_type: :stop`):
  Postgres drops a session's locks with the session, so a reconnected
  connection would be a leader without its lock. Instead the connection
  exits, and the leader stops with it (`{:lock_lost, reason}`). Postgrex
  pings an idle connection every second, so a dead database is noticed
  within about that.

  ## Joining before competing

  A node that is meant to be in a cluster (`settle_ms` above 0, which
  config/runtime.exs sets when DNS_CLUSTER_QUERY is) does not try for
  anything until it has joined: as soon as it sees another node it runs
  `:global.sync/0` and finds the leader that is already there, and only if
  it is still alone after `settle_ms` does it go for the lock. With the
  lock this is no longer what keeps a restarted node from leading beside a
  live one (the lock does that), but it saves a connection per boot.

  ## Options

  - `name:` the global name.
  - `start:` a function of the global name, returning what `start_link`
    returns. `:ignore` (a process that is off in this environment) is
    remembered as `:off`, and nothing is retried.
  - `lock:` the connection options for the lock (default: the
    `Marginalia.Repo` connection settings), or `false` for no lock, which
    is `:global` alone, as before.
  - `lock_key:` what the lock is taken on (default: `name`). Tests use it
    to stand two contenders that cannot see each other's global names in
    front of one lock, the way a split does.
  """
  use GenServer

  require Logger

  @retry_ms 200..1_200
  # a node that found the lock taken and no leader in sight: it is cut off
  # from the holder, or the holder is dying; its session is checked again
  @wait_ms 1_000..2_000
  @poll_ms 100
  # the first int4 of pg_try_advisory_lock(int4, int4): "marg", so these
  # keys do not collide with another app's locks on the same server
  @lock_space 0x6D617267
  @conn_keys ~w(hostname port username password database socket socket_dir socket_options ssl parameters connect_timeout)a

  def child_spec(opts) do
    %{id: {__MODULE__, Keyword.fetch!(opts, :name)}, start: {__MODULE__, :start_link, [opts]}}
  end

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "The leader's pid, wherever it runs, or nil."
  def whereis(name) do
    case :global.whereis_name(name) do
      :undefined -> nil
      pid -> pid
    end
  end

  @doc """
  `:settling`, `:leader`, `:follower`, `:waiting` (no leader in sight and
  the lock is someone else's) or `:off`, for the singleton process `sup`
  on this node.
  """
  def role(sup), do: GenServer.call(sup, :role)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    settle = Keyword.get(opts, :settle_ms, Application.get_env(:marginalia, __MODULE__, [])[:settle_ms] || 0)
    name = Keyword.fetch!(opts, :name)

    state = %{
      name: name,
      start: Keyword.fetch!(opts, :start),
      lock: Keyword.get_lazy(opts, :lock, &repo_conn/0),
      lock_key: :erlang.phash2(Keyword.get(opts, :lock_key, name)),
      conn: nil,
      role: :settling,
      pid: nil,
      until: System.monotonic_time(:millisecond) + settle
    }

    if settle > 0, do: {:ok, state, {:continue, :settle}}, else: {:ok, claim(state)}
  end

  defp repo_conn, do: Marginalia.Repo.config() |> Keyword.take(@conn_keys)

  @impl true
  def handle_continue(:settle, state), do: settle(state)

  defp settle(state) do
    cond do
      Node.list() != [] ->
        # connected: make sure the name table includes what the others hold
        :global.sync()
        {:noreply, claim(state)}

      System.monotonic_time(:millisecond) >= state.until ->
        Logger.info("singleton #{inspect(state.name)}: alone after waiting, going for the lock",
          singleton: inspect(state.name)
        )

        {:noreply, claim(state)}

      true ->
        Process.send_after(self(), :settle, @poll_ms)
        {:noreply, state}
    end
  end

  # A leader in sight: follow it. None: take the lock, then the name.
  defp claim(state) do
    case whereis(state.name) do
      pid when is_pid(pid) -> follow(state, pid)
      nil -> lock_and_start(state)
    end
  end

  defp follow(state, pid) do
    Process.monitor(pid)
    %{state | role: :follower, pid: pid}
  end

  defp lock_and_start(state) do
    case acquire(state) do
      {:ok, conn} ->
        start(%{state | conn: conn})

      :taken ->
        wait(state)

      {:error, reason} ->
        # no database, no leader: say so, every time, and keep trying
        Logger.warning("singleton #{inspect(state.name)}: cannot reach Postgres for the lock: #{inspect(reason)}",
          singleton: inspect(state.name)
        )

        wait(state)
    end
  end

  defp start(state) do
    case state.start.({:global, state.name}) do
      {:ok, pid} ->
        Logger.info("singleton #{inspect(state.name)}: leader on #{node()}", singleton: inspect(state.name))
        %{state | role: :leader, pid: pid}

      {:error, {:already_started, pid}} ->
        # the last holder's process is still registered while it stops
        follow(release(state), pid)

      :ignore ->
        %{release(state) | role: :off, pid: nil}

      {:error, reason} ->
        exit(reason)
    end
  end

  defp wait(state) do
    Process.send_after(self(), :claim, Enum.random(@wait_ms))
    %{state | role: :waiting, pid: nil}
  end

  defp acquire(%{lock: false}), do: {:ok, nil}

  defp acquire(state) do
    opts = state.lock ++ [pool_size: 1, backoff_type: :stop, sync_connect: true]

    case Postgrex.start_link(opts) do
      {:ok, conn} ->
        case Postgrex.query(conn, "SELECT pg_try_advisory_lock($1, $2)", [@lock_space, state.lock_key]) do
          {:ok, %{rows: [[true]]}} ->
            {:ok, conn}

          {:ok, %{rows: [[false]]}} ->
            stop_conn(conn)
            :taken

          {:error, reason} ->
            stop_conn(conn)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  catch
    # a link exit from a connection that could not connect (trapped as a
    # message, but start_link can also exit the caller)
    :exit, reason -> {:error, reason}
  end

  defp release(%{conn: nil} = state), do: state

  defp release(state) do
    stop_conn(state.conn)
    %{state | conn: nil}
  end

  defp stop_conn(conn) do
    GenServer.stop(conn, :normal, 1_000)
  catch
    :exit, _ -> :ok
  end

  @impl true
  def handle_call(:role, _from, state), do: {:reply, state.role, state}

  @impl true
  # our leader stopped: so do we (closing the lock's session with us), and
  # the supervisor decides what next
  def handle_info({:EXIT, pid, reason}, %{pid: pid, role: :leader} = state) do
    {:stop, reason, release(%{state | pid: nil})}
  end

  # the lock's session is gone, so the lock is: the leader must not run on
  # without it, or another node takes the lock and there are two
  def handle_info({:EXIT, conn, reason}, %{conn: conn, role: :leader} = state) when conn != nil do
    Logger.error("singleton #{inspect(state.name)}: lost the lock's connection (#{inspect(reason)}), stopping the leader",
      singleton: inspect(state.name)
    )

    Process.exit(state.pid, {:lock_lost, reason})
    {:stop, {:lock_lost, reason}, %{state | conn: nil}}
  end

  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}

  # the leader elsewhere went away: wait a moment, then try to take over
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{pid: pid, role: :follower} = state) do
    Logger.info("singleton #{inspect(state.name)}: leader #{inspect(pid)} on #{node(pid)} went (#{inspect(reason)})",
      singleton: inspect(state.name)
    )

    Process.send_after(self(), :claim, Enum.random(@retry_ms))
    {:noreply, %{state | pid: nil}}
  end

  def handle_info(:settle, %{role: :settling} = state), do: settle(state)
  def handle_info(:claim, %{role: role, pid: nil} = state) when role in [:follower, :waiting], do: {:noreply, claim(state)}
  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state), do: release(state)
end
