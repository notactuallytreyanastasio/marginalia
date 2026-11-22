defmodule Marginalia.Singleton do
  @moduledoc """
  One of something for the whole cluster, whichever node it lands on.

  Every node runs one of these per name. Each tries to start the real
  process under a `:global` name; one wins and is the leader, linked to
  this process. The others are followers: they monitor the leader and,
  when it goes (its node stopped, crashed or was cut off), try again after
  a short random wait, so one of them takes over.

  Why not just start the process on every node: `Marginalia.Runs` exists
  to say "one run per key", and three nodes each holding their own table
  would each say yes. `Marginalia.Mutterings.Clock` asks a model for lines
  every half hour; three of them ask three times.

  ## Joining before competing

  A node that is meant to be in a cluster (`settle_ms` above 0, which
  config/runtime.exs sets when DNS_CLUSTER_QUERY is) does not claim
  anything until it has joined: as soon as it sees another node it runs
  `:global.sync/0` and finds the leader that is already there, and only if
  it is still alone after `settle_ms` does it take it to be the first node
  and lead. Claiming straight away was tried and is wrong: a node
  restarted in a rolling deploy booted alone, became a second leader,
  `Marginalia.Runs` swept the database (marking the live leader's runs
  failed), and when the two met `:global` killed one of them at random,
  as often as not the one with work in flight.

  Two nodes that did both lead (they booted together, or a network split
  healed) are still resolved by `:global`: it kills one, that process's
  exit stops this one, the supervisor starts it again, and it comes back
  as a follower.

  `start:` is a function of the global name, returning what `start_link`
  returns. `:ignore` (a process that is off in this environment) is
  remembered as `:off`, and nothing is retried.
  """
  use GenServer

  require Logger

  @retry_ms 200..1_200
  @poll_ms 100

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

  @doc "`:settling`, `:leader`, `:follower` or `:off`, for the singleton process `sup` on this node."
  def role(sup), do: GenServer.call(sup, :role)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    settle = Keyword.get(opts, :settle_ms, Application.get_env(:marginalia, __MODULE__, [])[:settle_ms] || 0)

    state = %{
      name: Keyword.fetch!(opts, :name),
      start: Keyword.fetch!(opts, :start),
      role: :settling,
      pid: nil,
      until: System.monotonic_time(:millisecond) + settle
    }

    if settle > 0, do: {:ok, state, {:continue, :settle}}, else: {:ok, claim(state)}
  end

  @impl true
  def handle_continue(:settle, state), do: settle(state)

  defp settle(state) do
    cond do
      Node.list() != [] ->
        # connected: make sure the name table includes what the others hold
        :global.sync()
        {:noreply, claim(state)}

      System.monotonic_time(:millisecond) >= state.until ->
        Logger.info("singleton #{inspect(state.name)}: alone after waiting, leading", singleton: inspect(state.name))
        {:noreply, claim(state)}

      true ->
        Process.send_after(self(), :settle, @poll_ms)
        {:noreply, state}
    end
  end

  defp claim(state) do
    case state.start.({:global, state.name}) do
      {:ok, pid} ->
        Logger.info("singleton #{inspect(state.name)}: leader on #{node()}", singleton: inspect(state.name))
        %{state | role: :leader, pid: pid}

      {:error, {:already_started, pid}} ->
        Process.monitor(pid)
        %{state | role: :follower, pid: pid}

      :ignore ->
        %{state | role: :off, pid: nil}

      {:error, reason} ->
        exit(reason)
    end
  end

  @impl true
  def handle_call(:role, _from, state), do: {:reply, state.role, state}

  @impl true
  # our leader stopped: so do we, and the supervisor decides what next
  def handle_info({:EXIT, pid, reason}, %{pid: pid, role: :leader} = state) do
    {:stop, reason, state}
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
  def handle_info(:claim, %{role: :follower, pid: nil} = state), do: {:noreply, claim(state)}
  def handle_info(_other, state), do: {:noreply, state}
end
