defmodule BlokusBomberman.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BlokusBombermanWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:blokus_bomberman, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: BlokusBomberman.PubSub},
      # Start a worker by calling: BlokusBomberman.Worker.start_link(arg)
      # {BlokusBomberman.Worker, arg},
      # Start to serve requests, typically the last entry
      BlokusBombermanWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BlokusBomberman.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BlokusBombermanWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
