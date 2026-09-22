defmodule Marginalia.Mutterings.ClockTest do
  @moduledoc """
  The cron. Seeds first, tops up after, survives a failing call, and does
  not start at all when told not to.
  """
  use Marginalia.DataCase, async: false

  alias Marginalia.Mutterings
  alias Marginalia.Mutterings.Clock

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})
    :ok
  end

  defp lines(n), do: {:ok, Enum.map_join(1..n, "\n", &"Tick #{&1}.")}

  defp wait_until(fun, tries \\ 100) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("never happened")
      true -> Process.sleep(10) && wait_until(fun, tries - 1)
    end
  end

  test "seeds to a hundred on the first tick, then adds ten a tick" do
    start_supervised!({Clock, name: :clock_a, enabled: true, first: 0, every: 30, call: &lines/1})

    wait_until(fn -> Mutterings.count() >= 100 end)
    assert Mutterings.count() == 100

    wait_until(fn -> Mutterings.count() >= 120 end)
    assert Mutterings.count() >= 120
  end

  test "a call that fails, or raises, is a log line and the next tick" do
    parent = self()
    counter = :counters.new(1, [])

    call = fn n ->
      k = :counters.get(counter, 1)
      :counters.add(counter, 1, 1)
      send(parent, {:called, k})

      case k do
        0 -> {:error, :rate_limited}
        1 -> raise "boom"
        _ -> lines(n)
      end
    end

    start_supervised!({Clock, name: :clock_b, enabled: true, first: 0, every: 20, call: call})

    assert_receive {:called, 0}, 1_000
    assert_receive {:called, 1}, 1_000
    assert_receive {:called, 2}, 1_000
    wait_until(fn -> Mutterings.count() >= 100 end)
  end

  test "disabled means nothing runs" do
    assert {:ok, :undefined} = start_supervised({Clock, name: :clock_c, enabled: false, first: 0})
    Process.sleep(30)
    assert Mutterings.count() == 0
  end

  test "the application config keeps it off in test" do
    assert Application.get_env(:marginalia, Clock)[:enabled] == false
  end
end
