defmodule Marginalia.RunsTest do
  @moduledoc """
  Work that outlives the page that asked for it.

  The thing being tested is a negative: that killing the process which
  started a run does not kill the run. That was the behaviour of
  `start_async/3` in a LiveView, where the task is linked to the socket, and
  it meant a dropped websocket destroyed a forward read of a hundred and
  forty-seven documents — two hours of sequential model calls, already paid
  for, gone because somebody's wifi blinked.
  """
  use ExUnit.Case, async: false

  alias Marginalia.Runs

  setup do
    key = {:test, System.unique_integer([:positive])}
    on_exit(fn -> Runs.forget(key) end)
    %{key: key}
  end

  # A run that will not finish until this test says so, so there is a
  # window in which to look at it and to kill things.
  defp held(key, kind) do
    me = self()

    {:ok, _} =
      Runs.start(key, kind, fn ->
        send(me, {:running, self()})

        receive do
          {:finish, value} -> value
          :crash -> raise "asked to crash"
        after
          5_000 -> :timed_out
        end
      end)

    assert_receive {:running, pid}, 1_000
    pid
  end

  test "the run survives the process that started it", %{key: key} do
    me = self()

    starter =
      spawn(fn ->
        {:ok, _} =
          Runs.start(key, :read, fn ->
            send(me, {:running, self()})
            receive do: ({:finish, v} -> v), after: (5_000 -> :timed_out)
          end)

        send(me, :started)
        receive do: (:never -> :ok)
      end)

    assert_receive :started, 1_000
    assert_receive {:running, worker}, 1_000

    Process.exit(starter, :kill)
    refute Process.alive?(starter)

    # the point of the whole module
    Process.sleep(50)
    assert Process.alive?(worker), "killing the starter must not take the work with it"
    assert %{kind: :read} = Runs.get(key)

    send(worker, {:finish, :done})
    Process.sleep(50)
    refute Runs.running?(key)
  end

  test "a page that arrives late finds the run in flight", %{key: key} do
    worker = held(key, :compose)

    # what a fresh mount does
    assert %{kind: :compose, done: 0} = Runs.get(key)
    assert Runs.running?(key)

    send(worker, {:finish, :ok})
  end

  test "a second run on the same key is refused by name", %{key: key} do
    worker = held(key, :read)

    assert {:error, {:already_running, :read}} = Runs.start(key, :deepen, fn -> :ok end)
    assert {:error, {:already_running, :read}} = Runs.start(key, :read, fn -> :ok end)

    send(worker, {:finish, :ok})
  end

  test "another key is not blocked by this one", %{key: key} do
    other = {:test, System.unique_integer([:positive])}
    on_exit(fn -> Runs.forget(other) end)

    worker = held(key, :read)
    assert {:ok, _} = Runs.start(other, :read, fn -> :ok end)

    send(worker, {:finish, :ok})
  end

  describe "what subscribers hear" do
    setup %{key: key} do
      Runs.subscribe(key)
      :ok
    end

    test "started, then progress, then done", %{key: key} do
      worker = held(key, :read)

      assert_receive {:run, :started, %{kind: :read, done: 0}}

      Runs.progress(key, done: 3, total: 12)
      assert_receive {:run, :progress, %{done: 3, total: 12}}
      assert %{done: 3, total: 12} = Runs.get(key)

      send(worker, {:finish, {:errors, 0}})
      assert_receive {:run, :done, :read, {:errors, 0}}
      refute Runs.running?(key)
    end

    test "a stage, for work that has no count to report", %{key: key} do
      worker = held(key, :compose)
      assert_receive {:run, :started, _}

      Runs.progress(key, stage: "outlining")
      assert_receive {:run, :progress, %{stage: "outlining"}}

      Runs.progress(key, stage: "writing", done: 2, total: 5)
      assert_receive {:run, :progress, %{stage: "writing", done: 2, total: 5}}

      send(worker, {:finish, :ok})
      assert_receive {:run, :done, :compose, :ok}
    end

    test "a crash is announced and the key is freed", %{key: key} do
      worker = held(key, :read)
      assert_receive {:run, :started, _}

      send(worker, :crash)

      assert_receive {:run, :crashed, :read, _reason}, 2_000
      refute Runs.running?(key)

      # and the folder is not wedged afterwards
      assert {:ok, _} = Runs.start(key, :read, fn -> :ok end)
    end

    test "progress for a key with nothing running is dropped, not stored", %{key: key} do
      Runs.progress(key, done: 9)
      refute_receive {:run, :progress, _}, 100
      assert Runs.get(key) == nil
    end
  end

  test "an error returned by the work reaches the page as a value", %{key: key} do
    Runs.subscribe(key)
    worker = held(key, :compose)

    send(worker, {:finish, {:error, :not_read}})
    assert_receive {:run, :done, :compose, {:error, :not_read}}
  end
end
