defmodule AuthCanary.SetupTest do
  use ExUnit.Case, async: false

  setup do
    prev_req_opts = Application.get_env(:req, :default_options)

    Application.put_env(:auth_canary, :zitadel_url, "http://test.zitadel.local")
    Application.put_env(:auth_canary, :zitadel_tls_verify, false)
    Application.put_env(:auth_canary, :bao_addr, "http://test.bao.local")
    Application.put_env(:auth_canary, :bao_role, "test-role")
    Application.put_env(:auth_canary, :bao_secret_path, "test-secret")
    Application.put_env(:auth_canary, :bao_kv_mount, "secret")
    Application.put_env(:auth_canary, :bao_jwt_mount, "auth/jwt")
    Application.put_env(:auth_canary, :bao_tls_verify, false)
    Application.put_env(:auth_canary, :bao_admin_token, "test-bao-admin-token")
    Application.put_env(:auth_canary, :zitadel_key_file_path, nil)

    on_exit(fn ->
      Application.delete_env(:auth_canary, :zitadel_admin_token)
      Application.delete_env(:auth_canary, :zitadel_key_file_path)

      if prev_req_opts,
        do: Application.put_env(:req, :default_options, prev_req_opts),
        else: Application.delete_env(:req, :default_options)
    end)

    :ok
  end

  describe "run/0 with no admin token" do
    test "exits :ok when ZITADEL_ADMIN_TOKEN not set" do
      Application.delete_env(:auth_canary, :zitadel_admin_token)
      assert :ok = AuthCanary.Setup.run()
    end

    test "makes no HTTP calls when admin token is absent" do
      Application.delete_env(:auth_canary, :zitadel_admin_token)

      call_count = :counters.new(1, [])

      Req.Test.stub(:setup_no_token, fn conn ->
        :counters.add(call_count, 1, 1)
        Plug.Conn.send_resp(conn, 200, "should not be called")
      end)

      Application.put_env(:req, :default_options, plug: {Req.Test, :setup_no_token})

      AuthCanary.Setup.run()
      assert :counters.get(call_count, 1) == 0
    end
  end

  describe "run/0 with Zitadel admin token (all resources exist)" do
    setup do
      Application.put_env(:auth_canary, :zitadel_admin_token, "test-admin-token")
      :ok
    end

    test "skips create calls when project already exists" do
      tmp_key = "/tmp/test_key_exists_#{:rand.uniform(999_999)}.json"
      File.write!(tmp_key, Jason.encode!(%{"userId" => "user-123", "type" => "serviceAccount"}))
      Application.put_env(:auth_canary, :zitadel_key_file_path, tmp_key)
      on_exit(fn -> File.rm(tmp_key) end)

      create_call_count = :counters.new(1, [])

      Req.Test.stub(:setup_exists, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/management/v1/projects/_search"} ->
            Req.Test.json(conn, %{"result" => [%{"id" => "proj-123"}]})

          {"POST", "/management/v1/projects/proj-123/apps/_search"} ->
            Req.Test.json(conn, %{
              "result" => [
                %{"id" => "app-123", "apiConfig" => %{"clientId" => "client-123"}}
              ]
            })

          {"POST", "/management/v1/users/_search"} ->
            Req.Test.json(conn, %{"result" => [%{"id" => "user-123"}]})

          {"GET", "/management/v1/users/user-123/grants"} ->
            Req.Test.json(conn, %{"result" => [%{"projectId" => "proj-123"}]})

          {"GET", "/v1/auth/jwt/role/test-role"} ->
            Req.Test.json(conn, %{
              "data" => %{"bound_audiences" => ["http://test.zitadel.local"]}
            })

          {"GET", "/v1/secret/data/test-secret"} ->
            Req.Test.json(conn, %{"data" => %{"canary" => "ok"}})

          {"POST", _path} ->
            :counters.add(create_call_count, 1, 1)
            Req.Test.json(conn, %{})

          _ ->
            Plug.Conn.send_resp(conn, 404, "not found")
        end
      end)

      Application.put_env(:req, :default_options, plug: {Req.Test, :setup_exists})

      assert :ok = AuthCanary.Setup.run()
      assert :counters.get(create_call_count, 1) == 0
    end

    test "calls create project when project absent" do
      create_project_called = :counters.new(1, [])

      Req.Test.stub(:setup_no_project, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/management/v1/projects/_search"} ->
            Req.Test.json(conn, %{})

          {"POST", "/management/v1/projects"} ->
            :counters.add(create_project_called, 1, 1)
            Req.Test.json(conn, %{"id" => "new-proj-456"})

          {"POST", "/management/v1/projects/new-proj-456/apps/_search"} ->
            Req.Test.json(conn, %{
              "result" => [
                %{"id" => "app-1", "apiConfig" => %{"clientId" => "client-456"}}
              ]
            })

          {"POST", "/management/v1/users/_search"} ->
            Req.Test.json(conn, %{"result" => [%{"id" => "user-456"}]})

          {"GET", "/management/v1/users/user-456/grants"} ->
            Req.Test.json(conn, %{"result" => [%{"projectId" => "new-proj-456"}]})

          {"POST", "/management/v1/users/user-456/keys"} ->
            Req.Test.json(conn, %{"userId" => "user-456", "key" => "key-data"})

          {"GET", "/v1/auth/jwt/role/test-role"} ->
            Req.Test.json(conn, %{
              "data" => %{"bound_audiences" => ["http://test.zitadel.local"]}
            })

          {"GET", "/v1/secret/data/test-secret"} ->
            Req.Test.json(conn, %{"data" => %{"canary" => "ok"}})

          _ ->
            Plug.Conn.send_resp(conn, 404, "not found")
        end
      end)

      Application.put_env(:req, :default_options, plug: {Req.Test, :setup_no_project})

      assert :ok = AuthCanary.Setup.run()
      assert :counters.get(create_project_called, 1) == 1
    end

    test "regenerates key when key file userId mismatches" do
      tmp_key = "/tmp/test_key_#{:rand.uniform(999_999)}.json"
      Application.put_env(:auth_canary, :zitadel_key_file_path, tmp_key)

      File.write!(tmp_key, Jason.encode!(%{"userId" => "OLD_USER_ID", "type" => "serviceAccount"}))
      on_exit(fn -> File.rm(tmp_key) end)

      create_key_called = :counters.new(1, [])

      Req.Test.stub(:setup_stale_key, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/management/v1/projects/_search"} ->
            Req.Test.json(conn, %{"result" => [%{"id" => "proj-123"}]})

          {"POST", "/management/v1/projects/proj-123/apps/_search"} ->
            Req.Test.json(conn, %{
              "result" => [%{"id" => "app-1", "apiConfig" => %{"clientId" => "client-123"}}]
            })

          {"POST", "/management/v1/users/_search"} ->
            Req.Test.json(conn, %{"result" => [%{"id" => "NEW_USER_ID"}]})

          {"GET", "/management/v1/users/NEW_USER_ID/grants"} ->
            Req.Test.json(conn, %{"result" => [%{"projectId" => "proj-123"}]})

          {"POST", "/management/v1/users/NEW_USER_ID/keys"} ->
            :counters.add(create_key_called, 1, 1)
            Req.Test.json(conn, %{"userId" => "NEW_USER_ID", "key" => "new-key-data"})

          {"GET", "/v1/auth/jwt/role/test-role"} ->
            Req.Test.json(conn, %{
              "data" => %{"bound_audiences" => ["http://test.zitadel.local"]}
            })

          {"GET", "/v1/secret/data/test-secret"} ->
            Req.Test.json(conn, %{"data" => %{"canary" => "ok"}})

          _ ->
            Plug.Conn.send_resp(conn, 404, "not found")
        end
      end)

      Application.put_env(:req, :default_options, plug: {Req.Test, :setup_stale_key})

      # Should not raise (mismatch triggers key regen, not an error)
      AuthCanary.Setup.run()
      assert :counters.get(create_key_called, 1) == 1
    end

    test "key file has 0o600 permissions after being written" do
      tmp_key = "/tmp/test_key_perms_#{:rand.uniform(999_999)}.json"
      Application.put_env(:auth_canary, :zitadel_key_file_path, tmp_key)
      on_exit(fn -> File.rm(tmp_key) end)

      Req.Test.stub(:setup_key_perms, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/management/v1/projects/_search"} ->
            Req.Test.json(conn, %{"result" => [%{"id" => "proj-123"}]})

          {"POST", "/management/v1/projects/proj-123/apps/_search"} ->
            Req.Test.json(conn, %{
              "result" => [%{"id" => "app-1", "apiConfig" => %{"clientId" => "client-123"}}]
            })

          {"POST", "/management/v1/users/_search"} ->
            Req.Test.json(conn, %{"result" => [%{"id" => "user-perm"}]})

          {"GET", "/management/v1/users/user-perm/grants"} ->
            Req.Test.json(conn, %{"result" => [%{"projectId" => "proj-123"}]})

          {"POST", "/management/v1/users/user-perm/keys"} ->
            Req.Test.json(conn, %{"userId" => "user-perm", "keyData" => "test"})

          {"GET", "/v1/auth/jwt/role/test-role"} ->
            Req.Test.json(conn, %{
              "data" => %{"bound_audiences" => ["http://test.zitadel.local"]}
            })

          {"GET", "/v1/secret/data/test-secret"} ->
            Req.Test.json(conn, %{"data" => %{"canary" => "ok"}})

          _ ->
            Plug.Conn.send_resp(conn, 404, "not found")
        end
      end)

      Application.put_env(:req, :default_options, plug: {Req.Test, :setup_key_perms})

      AuthCanary.Setup.run()

      assert File.exists?(tmp_key)
      {:ok, stat} = File.stat(tmp_key)
      assert Bitwise.band(stat.mode, 0o777) == 0o600
    end

    test "does not overwrite OpenBao role when bound_audiences have drifted" do
      post_role_called = :counters.new(1, [])

      Req.Test.stub(:setup_role_drift, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/management/v1/projects/_search"} ->
            Req.Test.json(conn, %{"result" => [%{"id" => "proj-123"}]})

          {"POST", "/management/v1/projects/proj-123/apps/_search"} ->
            Req.Test.json(conn, %{
              "result" => [%{"id" => "app-1", "apiConfig" => %{"clientId" => "client-drift"}}]
            })

          {"POST", "/management/v1/users/_search"} ->
            Req.Test.json(conn, %{"result" => [%{"id" => "user-drift"}]})

          {"GET", "/management/v1/users/user-drift/grants"} ->
            Req.Test.json(conn, %{"result" => [%{"projectId" => "proj-123"}]})

          {"POST", "/management/v1/users/user-drift/keys"} ->
            Req.Test.json(conn, %{"userId" => "user-drift", "key" => "key-data"})

          {"GET", "/v1/auth/jwt/role/test-role"} ->
            Req.Test.json(conn, %{
              "data" => %{"bound_audiences" => ["https://wrong-issuer.com"]}
            })

          {"POST", "/v1/auth/jwt/role/test-role"} ->
            :counters.add(post_role_called, 1, 1)
            Req.Test.json(conn, %{})

          {"GET", "/v1/secret/data/test-secret"} ->
            Req.Test.json(conn, %{"data" => %{"canary" => "ok"}})

          _ ->
            Plug.Conn.send_resp(conn, 404, "not found")
        end
      end)

      Application.put_env(:req, :default_options, plug: {Req.Test, :setup_role_drift})

      AuthCanary.Setup.run()
      assert :counters.get(post_role_called, 1) == 0
    end

    test "creates OpenBao secret placeholder when absent" do
      create_secret_called = :counters.new(1, [])

      Req.Test.stub(:setup_secret_absent, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/management/v1/projects/_search"} ->
            Req.Test.json(conn, %{"result" => [%{"id" => "proj-123"}]})

          {"POST", "/management/v1/projects/proj-123/apps/_search"} ->
            Req.Test.json(conn, %{
              "result" => [%{"id" => "app-1", "apiConfig" => %{"clientId" => "client-123"}}]
            })

          {"POST", "/management/v1/users/_search"} ->
            Req.Test.json(conn, %{"result" => [%{"id" => "user-123"}]})

          {"GET", "/management/v1/users/user-123/grants"} ->
            Req.Test.json(conn, %{"result" => [%{"projectId" => "proj-123"}]})

          {"POST", "/management/v1/users/user-123/keys"} ->
            Req.Test.json(conn, %{"userId" => "user-123", "key" => "key-data"})

          {"GET", "/v1/auth/jwt/role/test-role"} ->
            Req.Test.json(conn, %{
              "data" => %{"bound_audiences" => ["http://test.zitadel.local"]}
            })

          {"GET", "/v1/secret/data/test-secret"} ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(404, Jason.encode!(%{"errors" => []}))

          {"POST", "/v1/secret/data/test-secret"} ->
            :counters.add(create_secret_called, 1, 1)
            Req.Test.json(conn, %{"data" => %{}})

          _ ->
            Plug.Conn.send_resp(conn, 404, "not found")
        end
      end)

      Application.put_env(:req, :default_options, plug: {Req.Test, :setup_secret_absent})

      assert :ok = AuthCanary.Setup.run()
      assert :counters.get(create_secret_called, 1) == 1
    end

    test "idempotency: second run makes zero create calls" do
      tmp_key = "/tmp/test_key_idem_#{:rand.uniform(999_999)}.json"
      File.write!(tmp_key, Jason.encode!(%{"userId" => "user-123", "type" => "serviceAccount"}))
      Application.put_env(:auth_canary, :zitadel_key_file_path, tmp_key)
      on_exit(fn -> File.rm(tmp_key) end)

      create_calls = :counters.new(1, [])

      Req.Test.stub(:setup_idempotent, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/management/v1/projects/_search"} ->
            Req.Test.json(conn, %{"result" => [%{"id" => "proj-123"}]})

          {"POST", "/management/v1/projects/proj-123/apps/_search"} ->
            Req.Test.json(conn, %{
              "result" => [%{"id" => "app-1", "apiConfig" => %{"clientId" => "client-123"}}]
            })

          {"POST", "/management/v1/users/_search"} ->
            Req.Test.json(conn, %{"result" => [%{"id" => "user-123"}]})

          {"GET", "/management/v1/users/user-123/grants"} ->
            Req.Test.json(conn, %{"result" => [%{"projectId" => "proj-123"}]})

          {"GET", "/v1/auth/jwt/role/test-role"} ->
            Req.Test.json(conn, %{
              "data" => %{"bound_audiences" => ["http://test.zitadel.local"]}
            })

          {"GET", "/v1/secret/data/test-secret"} ->
            Req.Test.json(conn, %{"data" => %{"canary" => "ok"}})

          {"POST", _} ->
            :counters.add(create_calls, 1, 1)
            Req.Test.json(conn, %{})

          _ ->
            Plug.Conn.send_resp(conn, 404, "not found")
        end
      end)

      Application.put_env(:req, :default_options, plug: {Req.Test, :setup_idempotent})

      assert :ok = AuthCanary.Setup.run()
      assert :ok = AuthCanary.Setup.run()
      assert :counters.get(create_calls, 1) == 0
    end

    test "raises with step atom in message when Zitadel project search fails" do
      Req.Test.stub(:setup_project_fail, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/management/v1/projects/_search"} ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(500, Jason.encode!(%{"error" => "internal"}))

          _ ->
            Plug.Conn.send_resp(conn, 404, "not found")
        end
      end)

      Application.put_env(:req, :default_options, plug: {Req.Test, :setup_project_fail})

      assert_raise RuntimeError, ~r/zitadel_project/, fn ->
        AuthCanary.Setup.run()
      end
    end
  end
end
