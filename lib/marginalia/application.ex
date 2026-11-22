defmodule Marginalia.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MarginaliaWeb.Telemetry,
      Marginalia.Repo,
      {DNSCluster, query: Application.get_env(:marginalia, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Marginalia.PubSub},
      {Task.Supervisor, name: Marginalia.TaskSupervisor},
      Marginalia.Cache,
      # work that has to outlive the page that started it: one Runs server
      # for the cluster (Marginalia.Singleton), a copy of its table per node
      Marginalia.Runs.Mirror,
      {Marginalia.Singleton, name: Marginalia.Runs, start: &Marginalia.Runs.start_link(name: &1)},
      # one clock for the cluster, or every node asks the model for lines
      {Marginalia.Singleton,
       name: Marginalia.Mutterings.Clock, start: &Marginalia.Mutterings.Clock.start_link(name: &1)},
      # Start a worker by calling: Marginalia.Worker.start_link(arg)
      # {Marginalia.Worker, arg},
      # Start to serve requests, typically the last entry
      MarginaliaWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Marginalia.Supervisor]
    # Anything left mid-read by the last release is swept by whichever node
    # becomes the Runs server (Marginalia.Runs.init/1), not by every node at
    # boot: a node restarting next to a live server would mark that server's
    # runs failed. Marginalia.Recovery as a child of its own (origin/main,
    # 81161a8) did exactly that on a cluster, so it is not started here. On
    # a cluster's first boot the leader is decided after up to 8 s alone
    # (Marginalia.Singleton), so for that long a stale row can be served.
    Supervisor.start_link(children ++ factory_report(), opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  # The report the factory (obs_factor) reads: the BEAM, every connected
  # LiveView, and counted streams, on an internal port. On in production only
  # (config/prod.exs), so dev and test never bind the port.
  defp factory_report do
    if Application.get_env(:marginalia, :factory_report, false) do
      [{FactoryReport, app: :marginalia, repos: [Marginalia.Repo]}]
    else
      []
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    MarginaliaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
