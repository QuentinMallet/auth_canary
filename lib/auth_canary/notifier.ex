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

      http_post = Application.get_env(:auth_canary, :http_post, &Req.post/2)

      case http_post.(url, json: payload, receive_timeout: 5_000) do
        {:ok, %{status: s}} when s in 200..299 ->
          Logger.debug("notifier.sent", step: step, status: s)

        {:ok, %{status: s}} ->
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

  defp node_name, do: node() |> to_string() |> String.replace("nonode@nohost", hostname())

  defp hostname do
    case :inet.gethostname() do
      {:ok, name} -> to_string(name)
      _ -> "unknown"
    end
  end
end
