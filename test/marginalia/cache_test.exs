defmodule Marginalia.CacheTest do
  @moduledoc """
  Holding the public list of pairs in ETS.

  The cache knows nothing about links: the expensive thing is passed in. That
  is what lets these run without a database, and it is why the interesting
  cases — a miss, an invalidation, an expiry — are testable at all.
  """
  use ExUnit.Case, async: false

  alias Marginalia.Cache

  setup do
    Cache.invalidate_all()
    on_exit(&Cache.invalidate_all/0)
    :ok
  end

  test "the first call computes and the second does not" do
    me = self()

    fun = fn ->
      send(me, :computed)
      [:a, :b]
    end

    assert Cache.fetch(:k, fun) == [:a, :b]
    assert_received :computed

    assert Cache.fetch(:k, fun) == [:a, :b]
    refute_received :computed, "the second call has to come out of the table"
  end

  test "invalidating makes the next call compute again" do
    me = self()
    fun = fn -> send(me, :computed) && [:x] end

    Cache.fetch(:k, fun)
    assert_received :computed

    Cache.invalidate(:k)

    Cache.fetch(:k, fun)
    assert_received :computed
  end

  test "peek does not compute anything" do
    assert Cache.peek(:k) == :miss

    Cache.fetch(:k, fn -> [:filled] end)
    assert Cache.peek(:k) == {:ok, [:filled]}
  end

  test "an entry past its ttl is recomputed" do
    me = self()
    fun = fn -> send(me, :computed) && [:fresh] end

    Cache.fetch(:k, fun, 50)
    assert_received :computed

    Process.sleep(60)

    Cache.fetch(:k, fun, 50)

    assert_received :computed,
                    "a missed invalidation must cost staleness until it expires, " <>
                      "not until somebody restarts the release"
  end

  test "an empty result is cached like any other" do
    me = self()
    fun = fn -> send(me, :computed) && [] end

    assert Cache.fetch(:k, fun) == []
    assert_received :computed

    assert Cache.fetch(:k, fun) == []
    refute_received :computed, "nothing to show is an answer, and recomputing it is the same cost"
  end

  test "reads do not go through the server process" do
    Cache.fetch(:k, fn -> [:x] end)

    # if a read were a GenServer call, killing the server mid-read would matter;
    # what is asserted here is only that the table is public and readable from
    # a process that has nothing to do with it
    task = Task.async(fn -> Cache.peek(:k) end)
    assert Task.await(task) == {:ok, [:x]}
  end

  test "two keys do not share an entry" do
    Cache.fetch(:one, fn -> [:first] end)
    Cache.fetch(:two, fn -> [:second] end)

    assert Cache.peek(:one) == {:ok, [:first]}
    assert Cache.peek(:two) == {:ok, [:second]}

    Cache.invalidate(:one)

    assert Cache.peek(:one) == :miss
    assert Cache.peek(:two) == {:ok, [:second]}, "invalidating one must not clear the other"
  end
end
