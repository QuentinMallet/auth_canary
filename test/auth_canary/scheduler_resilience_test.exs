defmodule AuthCanary.SchedulerResilienceTest do
  use ExUnit.Case, async: false
  # Snabbkaffe is an Erlang library; use its Erlang API directly
  # The resilience assertions use telemetry capture instead of snabbkaffe trace points
  # since the production code emits :telemetry events, not snabbkaffe trace points.

  @failure_threshold 3

  setup do
    Application.put_env(:auth_canary, :check_interval_ms, 299_000)
    Application.put_env(:auth_canary, :failure_threshold, @failure_threshold)
    # Delete spiffe_socket for instant failures (no gRPC socket timeout)
    prev_socket = Application.get_env(:auth_canary, :spiffe_socket)
    Application.delete_env(:auth_canary, :spiffe_socket)

    on_exit(fn ->
      if prev_socket,
        do: Application.put_env(:auth_canary, :spiffe_socket, prev_socket),
        else: Application.delete_env(:auth_canary, :spiffe_socket)
    end)

    :ok
  end

  defp send_tick_and_wait(pid, wait_ms \\ 200) do
    send(pid, :tick)
    :timer.sleep(wait_ms)
  end

  @tag :resilience
  test "scheduler restarts after crash under supervision" do
    child_spec = %{
      id: :test_scheduler,
      start: {GenServer, :start_link, [AuthCanary.Scheduler, [], []]},
      restart: :permanent
    }

    {:ok, sup_pid} = Supervisor.start_link([child_spec], strategy: :one_for_one)

    [{:test_scheduler, worker_pid, :worker, _}] = Supervisor.which_children(sup_pid)
    assert is_pid(worker_pid)

    Process.exit(worker_pid, :kill)
    :timer.sleep(500)

    [{:test_scheduler, new_pid, :worker, _}] = Supervisor.which_children(sup_pid)
    assert is_pid(new_pid)
    assert new_pid != worker_pid

    Supervisor.stop(sup_pid)
  end

  @tag :resilience
  test "5 consecutive failures emit degraded telemetry event exactly once" do
    test_pid = self()
    handler_id = "resilience-degraded-#{:erlang.unique_integer()}"

    :telemetry.attach(
      handler_id,
      [:auth_canary, :degraded],
      fn _event, measurements, _metadata, _config ->
        send(test_pid, {:degraded_event, measurements.count})
      end,
      nil
    )

    Application.put_env(:auth_canary, :failure_threshold, 3)

    {:ok, pid} = GenServer.start_link(AuthCanary.Scheduler, [])

    # 5 ticks, all fail instantly via rescue clause (no spiffe_socket)
    Enum.each(1..5, fn _ -> send_tick_and_wait(pid) end)

    state = :sys.get_state(pid, 5_000)
    assert state.consecutive_failures == 5
    assert state.degraded_emitted == true

    degraded_events = collect_messages(:degraded_event, 500)
    assert degraded_events == 1

    :telemetry.detach(handler_id)
    GenServer.stop(pid)
  end

  @tag :resilience
  test "scheduler survives rapid tick bursts without crashing" do
    {:ok, pid} = GenServer.start_link(AuthCanary.Scheduler, [])

    Enum.each(1..5, fn _ -> send_tick_and_wait(pid, 100) end)

    assert Process.alive?(pid)
    state = :sys.get_state(pid, 5_000)
    assert state.consecutive_failures >= 5

    GenServer.stop(pid)
  end

  defp collect_messages(tag, timeout) do
    receive do
      {^tag, _} -> 1 + collect_messages(tag, 100)
    after
      timeout -> 0
    end
  end
end
