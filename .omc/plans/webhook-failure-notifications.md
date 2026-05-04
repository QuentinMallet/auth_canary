# Plan: Configurable Webhook Failure Notifications

**Date:** 2026-05-02
**Complexity:** LOW-MEDIUM
**Scope:** 3 new/modified files + config additions

---

## RALPLAN-DR Summary

### Principles
1. **Optional by default** -- no webhook config = no notification, zero impact on existing behavior
2. **Minimal surface** -- hook into existing failure path, don't restructure the scheduler
3. **Sanitized payloads only** -- reuse existing `AuthCanary.Error.sanitize_reason/1`
4. **Fire-and-forget** -- webhook delivery must never block or crash the scheduler
5. **Threshold-based** -- avoid alert storms; fire once when degraded threshold is crossed

### Decision Drivers
1. **When to fire:** threshold crossing (matches existing `degraded_emitted` semantics) vs. every failure
2. **Payload format:** Prometheus AlertManager vs. Grafana webhook
3. **Module placement:** inline in scheduler vs. dedicated notifier module

### Viable Options

| # | Option | Pros | Cons |
|---|--------|------|------|
| 1 | **Prometheus AlertManager format, dedicated `Notifier` module, fire at threshold** | Clean separation; format matches simplex-alerter; deduplication built-in via `degraded_emitted` | Slightly more code than inline |
| 2 | Grafana webhook format, inline in scheduler, fire on every failure | Simpler initial impl; more granular alerts | Alert storm risk; Grafana format is less standard for alerting; pollutes scheduler |

**Chosen: Option 1** -- AlertManager format is the native protocol for simplex-alerter, threshold-based matches existing logic, and a dedicated module keeps scheduler clean.

**Option 2 invalidation:** Firing on every failure (every 60s) produces alert storms that desensitize operators. Grafana webhook format has no standard for grouping/deduplication.

---

## ADR

- **Decision:** Add `AuthCanary.Notifier` module using Prometheus AlertManager webhook format, triggered on degraded threshold crossing
- **Drivers:** simplex-alerter compatibility, alert deduplication, separation of concerns
- **Alternatives considered:** Grafana format + every-failure firing; telemetry handler approach
- **Why chosen:** Native simplex-alerter format, reuses existing threshold logic, minimal code change
- **Consequences:** Adds one new module, one env var, one config key; no new dependencies
- **Follow-ups:** Consider adding a "resolved" notification when pipeline recovers (future)

---

## Context

The auth_canary scheduler already:
- Tracks `consecutive_failures` counter
- Has a `failure_threshold` (default 5) config
- Emits `[:auth_canary, :degraded]` telemetry and sets `degraded_emitted: true` at threshold crossing
- Resets state on success

The simplex-alerter listens on `localhost:3334` and accepts Prometheus AlertManager webhook POSTs.

---

## Work Objectives

Add a configurable webhook URL that, when set, sends an AlertManager-formatted POST when the failure threshold is crossed. No notification if the URL is unset.

---

## Guardrails

**Must Have:**
- Webhook URL configurable via `WEBHOOK_URL` env var
- Payload follows Prometheus AlertManager webhook format
- Notification only fires at threshold crossing (same moment as `degraded_emitted` flip)
- Webhook failure logged but never crashes the scheduler
- Existing behavior unchanged when `WEBHOOK_URL` is unset

**Must NOT Have:**
- No new dependencies (Req + Jason already present)
- No retry logic for webhook delivery (keep it simple; simplex-alerter is local)
- No architecture changes to scheduler GenServer lifecycle

---

## Task Flow

### Step 1: Add config binding for webhook URL

**File:** `config/runtime.exs`

Add:
```elixir
config :auth_canary,
  webhook_url: System.get_env("WEBHOOK_URL")
```

**Acceptance criteria:** `Application.get_env(:auth_canary, :webhook_url)` returns `nil` when unset, URL string when set.

---

### Step 2: Create `AuthCanary.Notifier` module

**File:** `lib/auth_canary/notifier.ex`

```elixir
defmodule AuthCanary.Notifier do
  @moduledoc "Fire-and-forget webhook notifications for pipeline degradation"
  require Logger

  @doc """
  Sends an AlertManager-format webhook POST if WEBHOOK_URL is configured.
  Non-blocking: spawns a task, logs errors, never raises.
  """
  @spec notify_degraded(atom(), String.t(), non_neg_integer()) :: :ok
  def notify_degraded(step, reason, consecutive_failures) do
    case Application.get_env(:auth_canary, :webhook_url) do
      nil -> :ok
      url -> spawn_notification(url, step, reason, consecutive_failures)
    end
  end

  defp spawn_notification(url, step, reason, consecutive_failures) do
    Task.start(fn ->
      payload = build_payload(step, reason, consecutive_failures)

      case Req.post(url, json: payload, receive_timeout: 5_000) do
        {:ok, %Req.Response{status: s}} when s in 200..299 ->
          Logger.debug("notifier.sent", step: step, status: s)

        {:ok, %Req.Response{status: s}} ->
          Logger.warning("notifier.failed", step: step, status: s)

        {:error, reason} ->
          Logger.warning("notifier.error", step: step, error: inspect(reason))
      end
    end)

    :ok
  end

  defp build_payload(step, reason, consecutive_failures) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    [
      %{
        "status" => "firing",
        "labels" => %{
          "alertname" => "AuthCanaryDegraded",
          "severity" => "critical",
          "instance" => node_name(),
          "step" => to_string(step)
        },
        "annotations" => %{
          "summary" => "auth_canary pipeline degraded at step: #{step}",
          "description" => "#{consecutive_failures} consecutive failures. Last error: #{reason}"
        },
        "startsAt" => now,
        "generatorURL" => "auth_canary://#{node_name()}/scheduler"
      }
    ]
  end

  defp node_name, do: to_string(node()) |> String.replace("nonode@nohost", hostname())

  defp hostname do
    case :inet.gethostname() do
      {:ok, name} -> to_string(name)
      _ -> "unknown"
    end
  end
end
```

**Acceptance criteria:**
- Module compiles
- `notify_degraded/3` returns `:ok` immediately (non-blocking)
- When `webhook_url` is nil, no HTTP request is made
- Payload matches AlertManager format: list of alert objects with `status`, `labels`, `annotations`, `startsAt`

---

### Step 3: Wire `Notifier` into the scheduler's degraded path

**File:** `lib/auth_canary/scheduler.ex`

Modify `maybe_emit_degraded/1` (the clause where `n >= t` and `degraded_emitted: false`):

```elixir
defp maybe_emit_degraded(
       %{consecutive_failures: n, failure_threshold: t, degraded_emitted: false} = state
     )
     when n >= t do
  :telemetry.execute([:auth_canary, :degraded], %{count: n}, %{})
  Logger.critical("canary.degraded", count: n)
  AuthCanary.Notifier.notify_degraded(state.last_failed_step, state.last_failed_reason, n)
  %{state | degraded_emitted: true}
end
```

Also update `handle_result/3` for the error case to store step/reason in state:

```elixir
defp handle_result({:error, step, reason}, elapsed_ms, state) do
  new_failures = state.consecutive_failures + 1
  # ... existing logging and telemetry ...
  state = %{state | consecutive_failures: new_failures, last_failed_step: step, last_failed_reason: reason}
  maybe_emit_degraded(state)
end
```

And add to `init/1` state map:
```elixir
last_failed_step: nil,
last_failed_reason: nil
```

**Acceptance criteria:**
- `notify_degraded/3` is called exactly once when threshold is first crossed
- Not called on subsequent failures (guarded by `degraded_emitted: true`)
- Not called on recovery (state resets)
- Scheduler never crashes if Notifier fails

---

### Step 4: Add tests

**File:** `test/auth_canary/notifier_test.exs`

Tests to write:
1. `notify_degraded/3` with nil webhook_url does nothing (no HTTP call)
2. `notify_degraded/3` with configured URL sends correct AlertManager payload (use Bypass or Req.Test)
3. `notify_degraded/3` with unreachable URL logs warning but returns `:ok`
4. Integration: scheduler reaches threshold and triggers exactly one notification

**Acceptance criteria:**
- All tests pass
- No flaky async issues (use `Req.Test` adapter or `Bypass` for HTTP assertions)

---

## Exact Payload Format (AlertManager Webhook)

POST to `WEBHOOK_URL` with `Content-Type: application/json`:

```json
[
  {
    "status": "firing",
    "labels": {
      "alertname": "AuthCanaryDegraded",
      "severity": "critical",
      "instance": "auth-canary-host",
      "step": "zitadel"
    },
    "annotations": {
      "summary": "auth_canary pipeline degraded at step: zitadel",
      "description": "5 consecutive failures. Last error: http_401"
    },
    "startsAt": "2026-05-02T14:30:00.000Z",
    "generatorURL": "auth_canary://auth-canary-host/scheduler"
  }
]
```

---

## Environment Variable

| Var | Required | Default | Description |
|-----|----------|---------|-------------|
| `WEBHOOK_URL` | No | `nil` (disabled) | Full URL to POST AlertManager alerts (e.g. `http://localhost:3334/api/v1/alerts`) |

---

## Success Criteria

- [ ] `WEBHOOK_URL` unset: app starts and runs identically to before
- [ ] `WEBHOOK_URL` set: exactly one POST sent when failure threshold is crossed
- [ ] Payload is valid AlertManager webhook format accepted by simplex-alerter
- [ ] Webhook errors are logged, never crash the scheduler
- [ ] Tests cover all branches (nil URL, success, HTTP error, network error)
