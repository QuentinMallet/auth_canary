defmodule AuthCanary.OpenbaoTest do
  use ExUnit.Case, async: false

  setup do
    prev_addr = Application.get_env(:auth_canary, :bao_addr)
    prev_role = Application.get_env(:auth_canary, :bao_role)
    prev_secret = Application.get_env(:auth_canary, :bao_secret_path)
    prev_req_opts = Application.get_env(:req, :default_options)

    Application.put_env(:auth_canary, :bao_addr, "http://test.openbao.local")
    Application.put_env(:auth_canary, :bao_role, "test-role")
    Application.put_env(:auth_canary, :bao_secret_path, "test/secret")
    Application.put_env(:auth_canary, :bao_kv_mount, "secret")
    Application.put_env(:auth_canary, :bao_jwt_mount, "auth/jwt")
    Application.put_env(:auth_canary, :bao_ca_cert, nil)
    Application.put_env(:auth_canary, :bao_tls_verify, false)

    on_exit(fn ->
      if prev_addr,
        do: Application.put_env(:auth_canary, :bao_addr, prev_addr),
        else: Application.delete_env(:auth_canary, :bao_addr)

      if prev_role,
        do: Application.put_env(:auth_canary, :bao_role, prev_role),
        else: Application.delete_env(:auth_canary, :bao_role)

      if prev_secret,
        do: Application.put_env(:auth_canary, :bao_secret_path, prev_secret),
        else: Application.delete_env(:auth_canary, :bao_secret_path)

      if prev_req_opts,
        do: Application.put_env(:req, :default_options, prev_req_opts),
        else: Application.delete_env(:req, :default_options)
    end)

    :ok
  end

  describe "read_secret/1" do
    test "returns {:ok, body} on successful auth and secret read" do
      secret_body = %{"data" => %{"data" => %{"canary" => "health_check_ok"}}}

      Req.Test.stub(:openbao_stub, fn conn ->
        case conn.request_path do
          "/v1/auth/jwt/login" ->
            Req.Test.json(conn, %{"auth" => %{"client_token" => "test-client-token"}})

          "/v1/secret/data/test/secret" ->
            Req.Test.json(conn, secret_body)

          _ ->
            Plug.Conn.send_resp(conn, 404, "not found")
        end
      end)

      Application.put_env(:req, :default_options, plug: {Req.Test, :openbao_stub})

      assert {:ok, ^secret_body} = AuthCanary.Openbao.read_secret("test-oidc-token")
    end

    test "returns {:error, %Req.Response{}} when JWT auth fails with 403" do
      Req.Test.stub(:openbao_stub, fn conn ->
        case conn.request_path do
          "/v1/auth/jwt/login" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(403, Jason.encode!(%{"errors" => ["permission denied"]}))

          _ ->
            Plug.Conn.send_resp(conn, 404, "not found")
        end
      end)

      Application.put_env(:req, :default_options, plug: {Req.Test, :openbao_stub})

      assert {:error, %Req.Response{status: 403}} = AuthCanary.Openbao.read_secret("bad-token")
    end

    test "returns {:error, %Req.Response{}} when secret read fails with 404" do
      Req.Test.stub(:openbao_stub, fn conn ->
        case conn.request_path do
          "/v1/auth/jwt/login" ->
            Req.Test.json(conn, %{"auth" => %{"client_token" => "good-token"}})

          "/v1/secret/data/test/secret" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(404, Jason.encode!(%{"errors" => []}))

          _ ->
            Plug.Conn.send_resp(conn, 404, "not found")
        end
      end)

      Application.put_env(:req, :default_options, plug: {Req.Test, :openbao_stub})

      assert {:error, %Req.Response{status: 404}} = AuthCanary.Openbao.read_secret("good-token")
    end

    test "returns {:error, _} on connection failure at auth step" do
      Application.put_env(:auth_canary, :bao_addr, "http://localhost:1")
      Application.delete_env(:req, :default_options)

      assert {:error, _reason} = AuthCanary.Openbao.read_secret("test-token")
    end
  end
end
