defmodule Marginalia.SingletonTest do
  @moduledoc """
  Two Singletons with one name stand in for two nodes: the global name is
  the same whether the contenders are on one node or three. What a second
  node adds (the leader's node going away) arrives as the same :DOWN.
  """
  use ExUnit.Case, async: true

  alias Marginalia.Singleton

  defmodule Worker do
    use Agent
    def start_link(name), do: Agent.start_link(fn -> :ok end, name: name)
  end

  defp contender(name, opts \\ []) do
    {restart, opts} = Keyword.pop(opts, :restart, :permanent)

    start_supervised!(
      Supervisor.child_spec({Singleton, [name: name, start: &Worker.start_link/1] ++ opts},
        id: make_ref(),
        restart: restart
      )
    )
  end

  test "one leads, the other follows, and takes over when the leader goes" do
    name = {:singleton_test, make_ref()}
    a = contender(name)
    b = contender(name)

    assert Singleton.role(a) == :leader
    assert Singleton.role(b) == :follower
    leader = Singleton.whereis(name)
    assert is_pid(leader)

    ref = Process.monitor(a)
    Process.exit(leader, :kill)
    # the leader's Singleton stops with it (the test supervisor restarts it)
    assert_receive {:DOWN, ^ref, :process, ^a, :killed}, 2_000

    # within the follower's random wait, someone leads again under the name
    new = wait_for(fn -> Singleton.whereis(name) end)
    assert new != leader
  end

  test "a process that is off in this environment is :off, and nothing retries" do
    sup = start_supervised!({Singleton, name: {:off, make_ref()}, start: fn _ -> :ignore end})
    assert Singleton.role(sup) == :off
  end

  test "a node meant to cluster waits to join before leading, and leads alone after settle_ms" do
    name = {:settle, make_ref()}
    sup = start_supervised!({Singleton, name: name, start: &Worker.start_link/1, settle_ms: 300})
    # this test node is not distributed, so it never sees another node
    assert Singleton.role(sup) == :settling
    assert Singleton.whereis(name) == nil
    Process.sleep(450)
    assert Singleton.role(sup) == :leader
  end

  # A split, in one VM: two contenders under different global names can no
  # more see each other's leader than two nodes on either side of a
  # partition can. What they share is the lock, as the real nodes share
  # Postgres. Before the lock, each would have led.
  test "a contender that cannot see the leader waits on the lock, and leads only once the holder's session is gone" do
    key = make_ref()
    a = contender({:split_a, key}, lock_key: key, restart: :temporary)
    b = contender({:split_b, key}, lock_key: key)

    assert Singleton.role(a) == :leader
    assert Singleton.role(b) == :waiting
    assert Singleton.whereis({:split_b, key}) == nil

    # still waiting after a couple of its retries: the lock is held
    Process.sleep(2_500)
    assert Singleton.role(b) == :waiting

    ref = Process.monitor(a)
    Process.exit(Singleton.whereis({:split_a, key}), :kill)
    assert_receive {:DOWN, ^ref, :process, ^a, :killed}, 2_000

    assert is_pid(wait_for(fn -> Singleton.whereis({:split_b, key}) end, 80))
    assert Singleton.role(b) == :leader
  end

  test "a leader whose lock connection goes stops at once, and the lock is free for the next" do
    key = make_ref()
    a = contender({:lost_a, key}, lock_key: key, restart: :temporary)
    b = contender({:lost_b, key}, lock_key: key)
    leader = Singleton.whereis({:lost_a, key})
    assert Singleton.role(b) == :waiting

    lref = Process.monitor(leader)
    sref = Process.monitor(a)
    Process.exit(:sys.get_state(a).conn, :kill)

    assert_receive {:DOWN, ^lref, :process, ^leader, {:lock_lost, :killed}}, 1_000
    assert_receive {:DOWN, ^sref, :process, ^a, {:lock_lost, :killed}}, 1_000
    assert is_pid(wait_for(fn -> Singleton.whereis({:lost_b, key}) end, 80))
  end

  test "lock: false is :global alone: two contenders that cannot see each other both lead" do
    key = make_ref()
    a = contender({:nolock_a, key}, lock_key: key, lock: false)
    b = contender({:nolock_b, key}, lock_key: key, lock: false)
    assert Singleton.role(a) == :leader
    assert Singleton.role(b) == :leader
  end

  defp wait_for(fun, tries \\ 40) do
    case fun.() do
      nil when tries > 0 ->
        Process.sleep(50)
        wait_for(fun, tries - 1)

      value ->
        value
    end
  end
end
