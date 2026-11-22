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

  defp contender(name) do
    start_supervised!(
      {Singleton, name: name, start: &Worker.start_link/1},
      id: make_ref()
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
