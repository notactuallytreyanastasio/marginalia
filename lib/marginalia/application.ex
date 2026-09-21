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
      # work that has to outlive the page that started it
      Marginalia.Runs,
      # Start a worker by calling: Marginalia.Worker.start_link(arg)
      # {Marginalia.Worker, arg},
      # Start to serve requests, typically the last entry
      MarginaliaWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Marginalia.Supervisor]
    started = Supervisor.start_link(children, opts)

    # anything that was mid-read or mid-link when this release last stopped
    # has no process behind it any more — see Marginalia.Recovery
    if started != :ignore, do: Marginalia.Recovery.sweep()

    started
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MarginaliaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
