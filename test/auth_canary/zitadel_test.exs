defmodule AuthCanary.ZitadelTest do
  use ExUnit.Case, async: false

  setup do
    prev_addr = Application.get_env(:auth_canary, :zitadel_addr)
    prev_id = Application.get_env(:auth_canary, :zitadel_client_id)
    prev_secret = Application.get_env(:auth_canary, :zitadel_client_secret)
    prev_req_opts = Application.get_env(:req, :default_options)

    Application.put_env(:auth_canary, :zitadel_addr, "http://test.zitadel.local")
    Application.put_env(:auth_canary, :zitadel_client_id, "test-client-id")
    Application.put_env(:auth_canary, :zitadel_client_secret, "test-client-secret")

    on_exit(fn ->
      restore_env(:zitadel_addr, prev_addr)
      restore_env(:zitadel_client_id, prev_id)
      restore_env(:zitadel_client_secret, prev_secret)

      if prev_req_opts,
        do: Application.put_env(:req, :default_options, prev_req_opts),
        else: Application.delete_env(:req, :default_options)
    end)

    :ok
  end

  defp restore_env(key, nil), do: Application.delete_env(:auth_canary, key)
  defp restore_env(key, val), do: Application.put_env(:auth_canary, key, val)

  describe "fetch_access_token/0" do
    test "returns {:ok, access_token} on successful 200 response" do
      Req.Test.stub(:zitadel_stub, fn conn ->
        Req.Test.json(conn, %{"access_token" => "test_oidc_token_abc123"})
      end)

      Application.put_env(:req, :default_options, plug: {Req.Test, :zitadel_stub})

      assert {:ok, "test_oidc_token_abc123"} = AuthCanary.Zitadel.fetch_access_token()
    end

    test "returns {:error, {:http_error, 401, _}} on unauthorized" do
      Req.Test.stub(:zitadel_stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(401, Jason.encode!(%{"error" => "unauthorized"}))
      end)

      Application.put_env(:req, :default_options, plug: {Req.Test, :zitadel_stub})

      assert {:error, {:http_error, 401, _body}} = AuthCanary.Zitadel.fetch_access_token()
    end

    test "returns {:error, {:http_error, 400, _}} on bad request" do
      Req.Test.stub(:zitadel_stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, Jason.encode!(%{"error" => "invalid_request"}))
      end)

      Application.put_env(:req, :default_options, plug: {Req.Test, :zitadel_stub})

      assert {:error, {:http_error, 400, _body}} = AuthCanary.Zitadel.fetch_access_token()
    end

    test "returns {:error, :not_configured} when zitadel_addr is nil" do
      Application.delete_env(:auth_canary, :zitadel_addr)

      assert {:error, :not_configured} = AuthCanary.Zitadel.fetch_access_token()
    end

    test "returns {:error, :not_configured} when zitadel_client_id is nil" do
      Application.delete_env(:auth_canary, :zitadel_client_id)

      assert {:error, :not_configured} = AuthCanary.Zitadel.fetch_access_token()
    end

    test "returns {:error, {:request_failed, _}} on connection failure" do
      Application.put_env(:auth_canary, :zitadel_addr, "http://localhost:1")
      Application.delete_env(:req, :default_options)

      assert {:error, {:request_failed, _reason}} = AuthCanary.Zitadel.fetch_access_token()
    end
  end
end
