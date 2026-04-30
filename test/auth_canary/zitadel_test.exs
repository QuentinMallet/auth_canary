defmodule AuthCanary.ZitadelTest do
  use ExUnit.Case, async: false

  setup do
    prev_url = Application.get_env(:auth_canary, :zitadel_url)
    prev_req_opts = Application.get_env(:req, :default_options)

    Application.put_env(:auth_canary, :zitadel_url, "http://test.zitadel.local")
    Application.put_env(:auth_canary, :zitadel_ca_cert, nil)
    Application.put_env(:auth_canary, :zitadel_tls_verify, false)

    on_exit(fn ->
      if prev_url,
        do: Application.put_env(:auth_canary, :zitadel_url, prev_url),
        else: Application.delete_env(:auth_canary, :zitadel_url)

      if prev_req_opts,
        do: Application.put_env(:req, :default_options, prev_req_opts),
        else: Application.delete_env(:req, :default_options)
    end)

    :ok
  end

  describe "exchange_token/1" do
    test "returns {:ok, access_token} on successful 200 response" do
      Req.Test.stub(:zitadel_stub, fn conn ->
        Req.Test.json(conn, %{"access_token" => "test_oidc_token_abc123"})
      end)

      Application.put_env(:req, :default_options, plug: {Req.Test, :zitadel_stub})

      assert {:ok, "test_oidc_token_abc123"} = AuthCanary.Zitadel.exchange_token("test.jwt.svid")
    end

    test "returns {:error, %Req.Response{}} on 401 unauthorized" do
      Req.Test.stub(:zitadel_stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(401, Jason.encode!(%{"error" => "unauthorized"}))
      end)

      Application.put_env(:req, :default_options, plug: {Req.Test, :zitadel_stub})

      assert {:error, %Req.Response{status: 401}} = AuthCanary.Zitadel.exchange_token("bad.jwt")
    end

    test "returns {:error, %Req.Response{}} on 400 bad request" do
      Req.Test.stub(:zitadel_stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, Jason.encode!(%{"error" => "invalid_request"}))
      end)

      Application.put_env(:req, :default_options, plug: {Req.Test, :zitadel_stub})

      assert {:error, %Req.Response{status: 400}} = AuthCanary.Zitadel.exchange_token("bad.jwt")
    end

    test "returns {:error, _} on connection failure" do
      Application.put_env(:auth_canary, :zitadel_url, "http://localhost:1")
      Application.delete_env(:req, :default_options)

      assert {:error, _reason} = AuthCanary.Zitadel.exchange_token("test.jwt.svid")
    end
  end
end
