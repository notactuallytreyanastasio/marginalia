defmodule Marginalia.Mutterings.Clock do
  @moduledoc """
  The cron. Seeds the table shortly after boot, then tops it up every half
  hour, for as long as the node runs.

  There is no scheduler in this app and this does not justify adding one:
  it is one timer and one call. A missed tick costs nothing, because the
  table already holds what it holds, so the only thing this has to get
  right is to never take the application down. Every call is wrapped, and
  a failure is a log line and the next tick.

  It stays out of the way when there is no key: nothing is asked of a
  provider that is not configured, and the tick just comes round again.
  Off entirely in test, where `enabled: false` makes `init/1` return
  `:ignore` and the supervisor starts nothing.

  Options, from the application config under this module's name or from
  `start_link/1`: `:enabled`, `:every` (ms between top-ups), `:first`
  (ms before the seed), and `:call`, a function of `n` in place of the
  model, which is what a test hands it.
  """
  use GenServer

  require Logger

  alias Marginalia.{LLM, Mutterings}

  @every :timer.minutes(30)
  @first :timer.seconds(5)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  @impl true
  def init(opts) do
    cfg = Application.get_env(:marginalia, __MODULE__, []) |> Keyword.merge(opts)

    if Keyword.get(cfg, :enabled, true) do
      state = %{
        every: cfg[:every] || @every,
        call: cfg[:call],
        seeded: false
      }

      Process.send_after(self(), :tick, cfg[:first] || @first)
      {:ok, state}
    else
      :ignore
    end
  end

  @impl true
  def handle_info(:tick, state) do
    state =
      cond do
        is_nil(state.call) and not LLM.configured?() ->
          state

        not state.seeded ->
          case run(&Mutterings.seed/1, state) do
            {:ok, n} ->
              Logger.info("marginalia mutterings: seeded #{n}")
              %{state | seeded: true}

            _ ->
              state
          end

        true ->
          case run(&Mutterings.topup/1, state) do
            {:ok, n} -> Logger.info("marginalia mutterings: added #{n}")
            _ -> :ok
          end

          state
      end

    Process.send_after(self(), :tick, state.every)
    {:noreply, state}
  end

  defp run(fun, state) do
    opts = if state.call, do: [call: state.call], else: []

    case fun.(opts) do
      {:ok, n} ->
        {:ok, n}

      {:error, reason} ->
        Logger.warning("marginalia mutterings: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    e ->
      Logger.warning("marginalia mutterings: #{Exception.message(e)}")
      {:error, e}
  end
end
