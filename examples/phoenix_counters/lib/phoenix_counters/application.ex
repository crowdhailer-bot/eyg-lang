defmodule PhoenixCounters.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PhoenixCountersWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:phoenix_counters, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: PhoenixCounters.PubSub},
      # Start a worker by calling: PhoenixCounters.Worker.start_link(arg)
      # {PhoenixCounters.Worker, arg},
      # Start to serve requests, typically the last entry
      PhoenixCountersWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PhoenixCounters.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PhoenixCountersWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
