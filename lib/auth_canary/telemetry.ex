defmodule AuthCanary.Telemetry do
  use GenServer
  require Logger

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :telemetry.attach("auth-canary-cycle", [:auth_canary, :cycle], &handle_cycle/4, nil)
    :telemetry.attach("auth-canary-degraded", [:auth_canary, :degraded], &handle_degraded/4, nil)
    {:ok, %{}}
  end

  defp handle_cycle(_event, measurements, metadata, _config) do
    Logger.info("canary.cycle",
      elapsed_ms: measurements.elapsed_ms,
      result: metadata.result
    )
  end

  defp handle_degraded(_event, measurements, _metadata, _config) do
    Logger.critical("canary.degraded", count: measurements.count)
  end
end
