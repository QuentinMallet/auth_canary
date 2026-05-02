defmodule AuthCanary.NotifierTest do
  use ExUnit.Case, async: false

  setup do
    prev_url = Application.get_env(:auth_canary, :webhook_url)
    prev_post = Application.get_env(:auth_canary, :http_post)

    on_exit(fn ->
      if prev_url,
        do: Application.put_env(:auth_canary, :webhook_url, prev_url),
        else: Application.delete_env(:auth_canary, :webhook_url)

      if prev_post,
        do: Application.put_env(:auth_canary, :http_post, prev_post),
        else: Application.delete_env(:auth_canary, :http_post)
    end)

    :ok
  end

  describe "notify_degraded/3 with nil webhook_url" do
    test "returns :ok immediately and makes no HTTP request" do
      Application.delete_env(:auth_canary, :webhook_url)
      Application.put_env(:auth_canary, :http_post, fn _url, _opts ->
        raise "unexpected HTTP call"
      end)

      assert AuthCanary.Notifier.notify_degraded(:zitadel, "http_401", 5) == :ok
    end
  end

  describe "notify_degraded/3 with configured URL" do
    test "sends POST with correct AlertManager payload" do
      test_pid = self()

      Application.put_env(:auth_canary, :webhook_url, "http://localhost/alerts")
      Application.put_env(:auth_canary, :http_post, fn url, opts ->
        send(test_pid, {:request, url, opts[:json]})
        {:ok, %{status: 200}}
      end)

      assert AuthCanary.Notifier.notify_degraded(:zitadel, "http_401", 5) == :ok

      assert_receive {:request, url, payload}, 1_000

      assert url == "http://localhost/alerts"
      assert [alert] = payload
      assert alert["status"] == "firing"
      assert alert["labels"]["alertname"] == "AuthCanaryDegraded"
      assert alert["labels"]["severity"] == "critical"
      assert alert["labels"]["step"] == "zitadel"
      assert is_binary(alert["labels"]["instance"])
      assert alert["annotations"]["summary"] =~ "zitadel"
      assert alert["annotations"]["description"] =~ "5 consecutive failures"
      assert alert["annotations"]["description"] =~ "http_401"
      assert is_binary(alert["startsAt"])
      assert is_binary(alert["generatorURL"])
    end

    test "returns :ok when HTTP response is non-2xx" do
      Application.put_env(:auth_canary, :webhook_url, "http://localhost/alerts")
      Application.put_env(:auth_canary, :http_post, fn _url, _opts ->
        {:ok, %{status: 500}}
      end)

      assert AuthCanary.Notifier.notify_degraded(:bao, "timeout", 3) == :ok
      :timer.sleep(200)
    end

    test "returns :ok when HTTP call raises" do
      Application.put_env(:auth_canary, :webhook_url, "http://localhost/alerts")
      Application.put_env(:auth_canary, :http_post, fn _url, _opts ->
        {:error, %RuntimeError{message: "connection refused"}}
      end)

      assert AuthCanary.Notifier.notify_degraded(:spiffe, "connect_error", 7) == :ok
      :timer.sleep(200)
    end
  end
end
