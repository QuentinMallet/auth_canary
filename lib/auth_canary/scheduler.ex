defmodule AuthCanary.Scheduler do
  use GenServer
  require Logger
  alias AuthCanary.Pipeline

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    interval_ms = Application.fetch_env!(:auth_canary, :check_interval_ms)
    failure_threshold = Application.fetch_env!(:auth_canary, :failure_threshold)
    schedule_tick(interval_ms)

    {:ok,
     %{
       interval_ms: interval_ms,
       consecutive_failures: 0,
       failure_threshold: failure_threshold,
       degraded_emitted: false
     }}
  end

  @impl true
  def handle_info(:tick, state) do
    {elapsed_us, result} = :timer.tc(fn -> Pipeline.run() end)
    state = handle_result(result, div(elapsed_us, 1000), state)
    schedule_tick(state.interval_ms)
    {:noreply, state}
  rescue
    e -> handle_unexpected(e, state)
  catch
    kind, value -> handle_unexpected({kind, value}, state)
  end

  @impl true
  def terminate(_reason, _state) do
    Logger.info("canary.shutdown", reason: "scheduler terminating")
  end

  defp schedule_tick(ms), do: Process.send_after(self(), :tick, ms)

  defp handle_result({:ok, :success}, elapsed_ms, state) do
    Logger.info("canary.success", elapsed_ms: elapsed_ms)
    :telemetry.execute([:auth_canary, :cycle], %{elapsed_ms: elapsed_ms}, %{result: :success})
    %{state | consecutive_failures: 0, degraded_emitted: false}
  end

  defp handle_result({:error, step, reason}, elapsed_ms, state) do
    new_failures = state.consecutive_failures + 1

    Logger.warning("canary.failure",
      step: step,
      reason: reason,
      elapsed_ms: elapsed_ms,
      consecutive: new_failures
    )

    :telemetry.execute([:auth_canary, :cycle], %{elapsed_ms: elapsed_ms}, %{
      result: :failure,
      step: step
    })

    state = %{state | consecutive_failures: new_failures}
    maybe_emit_degraded(state)
  end

  defp maybe_emit_degraded(
         %{consecutive_failures: n, failure_threshold: t, degraded_emitted: false} = state
       )
       when n >= t do
    :telemetry.execute([:auth_canary, :degraded], %{count: n}, %{})
    Logger.critical("canary.degraded", count: n)
    %{state | degraded_emitted: true}
  end

  defp maybe_emit_degraded(state), do: state

  defp handle_unexpected(error, state) do
    new_failures = state.consecutive_failures + 1
    Logger.error("canary.unexpected", error: inspect(error), consecutive: new_failures)
    state = %{state | consecutive_failures: new_failures}
    state = maybe_emit_degraded(state)
    schedule_tick(state.interval_ms)
    {:noreply, state}
  end
end
