defmodule AuthCanary.Application do
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    ObservLib.configure()

    check_interval_ms = Application.fetch_env!(:auth_canary, :check_interval_ms)

    if check_interval_ms >= 300_000 do
      raise "CHECK_INTERVAL_MS must be < 300000ms (got #{check_interval_ms})"
    end

    spiffe_socket = Application.fetch_env!(:auth_canary, :spiffe_socket)

    children = [
      {SpiffeEx, socket_path: spiffe_socket},
      %{id: AuthCanary.Setup, start: {AuthCanary.Setup, :start_link, [[]]}, restart: :temporary},
      AuthCanary.Telemetry,
      AuthCanary.Scheduler
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: AuthCanary.Supervisor)
  end
end
