defmodule Marginalia.LinksCacheTest do
  @moduledoc """
  Holding the public list of pairs in ETS.

  The cache knows nothing about links: the expensive thing is passed in. That
  is what lets these run without a database, and it is why the interesting
  cases — a miss, an invalidation, an expiry — are testable at all.
  """
  use ExUnit.Case, async: false

  alias Marginalia.Links.Cache

  setup do
    Cache.invalidate()
    on_exit(&Cache.invalidate/0)
    :ok
  end

  test "the first call computes and the second does not" do
    me = self()

    fun = fn ->
      send(me, :computed)
      [:a, :b]
    end

    assert Cache.fetch(fun) == [:a, :b]
    assert_received :computed

    assert Cache.fetch(fun) == [:a, :b]
    refute_received :computed, "the second call has to come out of the table"
  end

  test "invalidating makes the next call compute again" do
    me = self()
    fun = fn -> send(me, :computed) && [:x] end

    Cache.fetch(fun)
    assert_received :computed

    Cache.invalidate()

    Cache.fetch(fun)
    assert_received :computed
  end

  test "peek does not compute anything" do
    assert Cache.peek() == :miss

    Cache.fetch(fn -> [:filled] end)
    assert Cache.peek() == {:ok, [:filled]}
  end

  test "an entry past its ttl is recomputed" do
    me = self()
    fun = fn -> send(me, :computed) && [:fresh] end

    Cache.fetch(fun, 50)
    assert_received :computed

    Process.sleep(60)

    Cache.fetch(fun, 50)

    assert_received :computed,
                    "a missed invalidation must cost staleness until it expires, " <>
                      "not until somebody restarts the release"
  end

  test "an empty result is cached like any other" do
    me = self()
    fun = fn -> send(me, :computed) && [] end

    assert Cache.fetch(fun) == []
    assert_received :computed

    assert Cache.fetch(fun) == []
    refute_received :computed, "nothing to show is an answer, and recomputing it is the same cost"
  end

  test "reads do not go through the server process" do
    Cache.fetch(fn -> [:x] end)

    # if a read were a GenServer call, killing the server mid-read would matter;
    # what is asserted here is only that the table is public and readable from
    # a process that has nothing to do with it
    task = Task.async(fn -> Cache.peek() end)
    assert Task.await(task) == {:ok, [:x]}
  end
end
