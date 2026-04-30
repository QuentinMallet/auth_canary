defmodule AuthCanary.SchedulerTest do
  use ExUnit.Case, async: false

  @failure_threshold 3

  setup do
    Application.put_env(:auth_canary, :check_interval_ms, 299_000)
    Application.put_env(:auth_canary, :failure_threshold, @failure_threshold)
    # Delete spiffe_socket so Pipeline.run/0 raises immediately via fetch_env!
    # This gives fast test cycles without waiting for gRPC socket timeouts.
    prev_socket = Application.get_env(:auth_canary, :spiffe_socket)

    Application.delete_env(:auth_canary, :spiffe_socket)

    on_exit(fn ->
      if prev_socket,
        do: Application.put_env(:auth_canary, :spiffe_socket, prev_socket),
        else: Application.delete_env(:auth_canary, :spiffe_socket)
    end)

    :ok
  end

  # Start Scheduler without name registration (bypass module's start_link)
  defp start_scheduler do
    GenServer.start_link(AuthCanary.Scheduler, [])
  end

  defp send_tick_and_wait(pid, wait_ms \\ 200) do
    send(pid, :tick)
    :timer.sleep(wait_ms)
  end

  describe "failure counter" do
    test "consecutive_failures starts at 0" do
      {:ok, pid} = start_scheduler()
      state = :sys.get_state(pid, 5_000)
      assert state.consecutive_failures == 0
      GenServer.stop(pid)
    end

    test "consecutive_failures increments by 1 on pipeline failure" do
      {:ok, pid} = start_scheduler()

      send_tick_and_wait(pid)

      state = :sys.get_state(pid, 5_000)
      assert state.consecutive_failures == 1
      GenServer.stop(pid)
    end

    test "consecutive_failures increments on each failure" do
      {:ok, pid} = start_scheduler()

      Enum.each(1..3, fn _ -> send_tick_and_wait(pid) end)

      state = :sys.get_state(pid, 5_000)
      assert state.consecutive_failures == 3
      GenServer.stop(pid)
    end

    test "degraded_emitted starts as false" do
      {:ok, pid} = start_scheduler()
      state = :sys.get_state(pid, 5_000)
      assert state.degraded_emitted == false
      GenServer.stop(pid)
    end
  end

  describe "degraded telemetry" do
    test "degraded fires exactly once at failure threshold crossing" do
      test_pid = self()
      handler_id = "test-degraded-#{:erlang.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:auth_canary, :degraded],
        fn _event, measurements, _metadata, _config ->
          send(test_pid, {:degraded, measurements.count})
        end,
        nil
      )

      {:ok, pid} = start_scheduler()

      # Send threshold+2 ticks — each fails instantly via rescue clause
      Enum.each(1..(@failure_threshold + 2), fn _ -> send_tick_and_wait(pid) end)

      degraded_count = collect_messages(:degraded, 500)
      assert degraded_count == 1

      :telemetry.detach(handler_id)
      GenServer.stop(pid)
    end

    test "degraded_emitted becomes true after threshold crossing" do
      {:ok, pid} = start_scheduler()

      Enum.each(1..(@failure_threshold + 1), fn _ -> send_tick_and_wait(pid) end)

      state = :sys.get_state(pid, 5_000)
      assert state.degraded_emitted == true
      GenServer.stop(pid)
    end

    test "degraded does not fire again when already emitted" do
      test_pid = self()
      handler_id = "test-degraded-no-double-#{:erlang.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:auth_canary, :degraded],
        fn _event, measurements, _metadata, _config ->
          send(test_pid, {:degraded, measurements.count})
        end,
        nil
      )

      {:ok, pid} = start_scheduler()

      Enum.each(1..(@failure_threshold * 2 + 1), fn _ -> send_tick_and_wait(pid) end)

      count = collect_messages(:degraded, 500)
      assert count == 1

      :telemetry.detach(handler_id)
      GenServer.stop(pid)
    end
  end

  describe "rescue/catch in handle_info" do
    test "scheduler continues after Pipeline raises (spiffe_socket env missing)" do
      {:ok, pid} = start_scheduler()
      assert Process.alive?(pid)

      send_tick_and_wait(pid)

      assert Process.alive?(pid)
      state = :sys.get_state(pid, 5_000)
      assert state.consecutive_failures == 1

      GenServer.stop(pid)
    end

    test "scheduler is not crashed by repeated exceptions in handle_info" do
      {:ok, pid} = start_scheduler()

      Enum.each(1..3, fn _ -> send_tick_and_wait(pid) end)

      assert Process.alive?(pid)
      state = :sys.get_state(pid, 5_000)
      assert state.consecutive_failures == 3

      GenServer.stop(pid)
    end
  end

  defp collect_messages(tag, timeout) do
    receive do
      {^tag, _} -> 1 + collect_messages(tag, 100)
    after
      timeout -> 0
    end
  end
end
