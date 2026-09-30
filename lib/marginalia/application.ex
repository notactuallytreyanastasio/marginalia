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
      # anything that was mid-read or mid-link when this release last stopped
      # has no process behind it any more. Runs once, after the Repo and
      # before the Endpoint, so no page is served a row still claiming to be
      # in flight. See Marginalia.Recovery.
      Marginalia.Recovery,
      # Start to serve requests, typically the last entry
      MarginaliaWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Marginalia.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MarginaliaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
