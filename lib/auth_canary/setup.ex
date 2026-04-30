defmodule AuthCanary.Setup do
  use Task, restart: :temporary
  require Logger
  alias AuthCanary.Error

  def start_link(_), do: Task.start_link(__MODULE__, :run, [])

  def run do
    admin_token = Application.get_env(:auth_canary, :zitadel_admin_token)

    unless admin_token do
      Logger.warning("setup.skipped", reason: "ZITADEL_ADMIN_TOKEN not set")
      :ok
    else
      run_setup(admin_token)
    end
  end

  defp run_setup(admin_token) do
    url = Application.fetch_env!(:auth_canary, :zitadel_url)
    ca_cert = Application.get_env(:auth_canary, :zitadel_ca_cert)
    tls_verify = Application.get_env(:auth_canary, :zitadel_tls_verify, true)
    transport = [transport_opts: tls_opts(ca_cert, tls_verify)]
    auth_header = [{"authorization", "Bearer #{admin_token}"}]

    project_id = ensure_zitadel_project(url, auth_header, transport)
    client_id = ensure_zitadel_app(url, project_id, auth_header, transport)
    user_id = ensure_zitadel_user(url, auth_header, transport)
    ensure_zitadel_grant(url, project_id, user_id, auth_header, transport)
    ensure_zitadel_key(url, user_id, auth_header, transport)

    ensure_openbao_role(client_id)
    ensure_openbao_secret()

    :ok
  end

  # --- Zitadel steps ---

  defp ensure_zitadel_project(url, auth_header, transport) do
    case Req.post("#{url}/management/v1/projects/_search",
           json: %{"queries" => [%{"nameQuery" => %{"name" => "canary", "method" => "TEXT_QUERY_METHOD_EQUALS"}}]},
           headers: auth_header,
           receive_timeout: 5_000,
           connect_options: transport
         ) do
      {:ok, %Req.Response{status: 200, body: %{"result" => [%{"id" => id} | _]}}} ->
        id

      {:ok, %Req.Response{status: 200}} ->
        case Req.post("#{url}/management/v1/projects",
               json: %{"name" => "canary"},
               headers: auth_header,
               receive_timeout: 5_000,
               connect_options: transport
             ) do
          {:ok, %Req.Response{status: 200, body: %{"id" => id}}} ->
            id

          {:ok, %Req.Response{} = resp} ->
            step_error!(:zitadel_project, resp)

          {:error, reason} ->
            step_error!(:zitadel_project, reason)
        end

      {:ok, %Req.Response{} = resp} ->
        step_error!(:zitadel_project, resp)

      {:error, reason} ->
        step_error!(:zitadel_project, reason)
    end
  end

  defp ensure_zitadel_app(url, project_id, auth_header, transport) do
    case Req.post("#{url}/management/v1/projects/#{project_id}/apps/_search",
           json: %{"queries" => [%{"nameQuery" => %{"name" => "canary server", "method" => "TEXT_QUERY_METHOD_EQUALS"}}]},
           headers: auth_header,
           receive_timeout: 5_000,
           connect_options: transport
         ) do
      {:ok, %Req.Response{status: 200, body: %{"result" => [%{"id" => _id, "apiConfig" => %{"clientId" => client_id}} | _]}}} ->
        client_id

      {:ok, %Req.Response{status: 200}} ->
        case Req.post("#{url}/management/v1/projects/#{project_id}/apps/api",
               json: %{"name" => "canary server", "authMethodType" => "API_AUTH_METHOD_TYPE_PRIVATE_KEY_JWT"},
               headers: auth_header,
               receive_timeout: 5_000,
               connect_options: transport
             ) do
          {:ok, %Req.Response{status: 200, body: %{"clientId" => client_id}}} ->
            client_id

          {:ok, %Req.Response{} = resp} ->
            step_error!(:zitadel_app, resp)

          {:error, reason} ->
            step_error!(:zitadel_app, reason)
        end

      {:ok, %Req.Response{} = resp} ->
        step_error!(:zitadel_app, resp)

      {:error, reason} ->
        step_error!(:zitadel_app, reason)
    end
  end

  defp ensure_zitadel_user(url, auth_header, transport) do
    case Req.post("#{url}/management/v1/users/_search",
           json: %{"queries" => [%{"userNameQuery" => %{"userName" => "auth-canary", "method" => "TEXT_QUERY_METHOD_EQUALS"}}]},
           headers: auth_header,
           receive_timeout: 5_000,
           connect_options: transport
         ) do
      {:ok, %Req.Response{status: 200, body: %{"result" => [%{"id" => id} | _]}}} ->
        id

      {:ok, %Req.Response{status: 200}} ->
        case Req.post("#{url}/management/v1/users/machine",
               json: %{"userName" => "auth-canary", "name" => "Auth Canary"},
               headers: auth_header,
               receive_timeout: 5_000,
               connect_options: transport
             ) do
          {:ok, %Req.Response{status: 200, body: %{"userId" => id}}} ->
            id

          {:ok, %Req.Response{} = resp} ->
            step_error!(:zitadel_user, resp)

          {:error, reason} ->
            step_error!(:zitadel_user, reason)
        end

      {:ok, %Req.Response{} = resp} ->
        step_error!(:zitadel_user, resp)

      {:error, reason} ->
        step_error!(:zitadel_user, reason)
    end
  end

  defp ensure_zitadel_grant(url, project_id, user_id, auth_header, transport) do
    case Req.get("#{url}/management/v1/users/#{user_id}/grants",
           headers: auth_header,
           receive_timeout: 5_000,
           connect_options: transport
         ) do
      {:ok, %Req.Response{status: 200, body: %{"result" => grants}}} when is_list(grants) ->
        already_granted =
          Enum.any?(grants, fn g -> Map.get(g, "projectId") == project_id end)

        unless already_granted do
          create_grant(url, project_id, user_id, auth_header, transport)
        end

      {:ok, %Req.Response{status: 200}} ->
        create_grant(url, project_id, user_id, auth_header, transport)

      {:ok, %Req.Response{} = resp} ->
        step_error!(:zitadel_grant, resp)

      {:error, reason} ->
        step_error!(:zitadel_grant, reason)
    end
  end

  defp create_grant(url, project_id, user_id, auth_header, transport) do
    case Req.post("#{url}/management/v1/projects/#{project_id}/grants",
           json: %{"userId" => user_id},
           headers: auth_header,
           receive_timeout: 5_000,
           connect_options: transport
         ) do
      {:ok, %Req.Response{status: 200}} ->
        :ok

      {:ok, %Req.Response{} = resp} ->
        step_error!(:zitadel_grant, resp)

      {:error, reason} ->
        step_error!(:zitadel_grant, reason)
    end
  end

  defp ensure_zitadel_key(url, user_id, auth_header, transport) do
    key_path = Application.get_env(:auth_canary, :zitadel_key_file_path)

    needs_new_key =
      if key_path && File.exists?(key_path) do
        case File.read(key_path) do
          {:ok, json} ->
            case Jason.decode(json) do
              {:ok, %{"userId" => stored_user_id}} when stored_user_id == user_id ->
                false

              {:ok, %{"userId" => _other}} ->
                Logger.warning("setup.stale_key",
                  reason: "key file userId mismatch — old key on Zitadel NOT auto-revoked; manual cleanup required"
                )
                true

              _ ->
                true
            end

          _ ->
            true
        end
      else
        true
      end

    if needs_new_key do
      create_and_write_key(url, user_id, key_path, auth_header, transport)
    end
  end

  defp create_and_write_key(url, user_id, key_path, auth_header, transport) do
    case Req.post("#{url}/management/v1/users/#{user_id}/keys",
           json: %{"type" => "KEY_TYPE_JSON"},
           headers: auth_header,
           receive_timeout: 5_000,
           connect_options: transport
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        if key_path do
          write_key_file(key_path, Jason.encode!(body))
        end

      {:ok, %Req.Response{} = resp} ->
        step_error!(:zitadel_key, resp)

      {:error, reason} ->
        step_error!(:zitadel_key, reason)
    end
  end

  defp write_key_file(path, json) do
    try do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, json)
      File.chmod!(path, 0o600)
    rescue
      e -> step_error!(:zitadel_key_write, e)
    end
  end

  # --- OpenBao steps ---

  defp ensure_openbao_role(client_id) do
    bao_addr = Application.fetch_env!(:auth_canary, :bao_addr)
    bao_role = Application.fetch_env!(:auth_canary, :bao_role)
    bao_jwt_mount = Application.get_env(:auth_canary, :bao_jwt_mount, "auth/jwt")
    bao_policy = Application.get_env(:auth_canary, :bao_policy, "auth-canary-read")
    bao_issuer = Application.get_env(:auth_canary, :bao_zitadel_issuer)
    zitadel_url = Application.fetch_env!(:auth_canary, :zitadel_url)
    bao_admin_token = Application.get_env(:auth_canary, :bao_admin_token)
    ca_cert = Application.get_env(:auth_canary, :bao_ca_cert)
    tls_verify = Application.get_env(:auth_canary, :bao_tls_verify, true)
    transport = [transport_opts: tls_opts(ca_cert, tls_verify)]
    vault_header = [{"x-vault-token", bao_admin_token || ""}]

    case Req.get("#{bao_addr}/v1/#{bao_jwt_mount}/role/#{bao_role}",
           headers: vault_header,
           receive_timeout: 5_000,
           connect_options: transport
         ) do
      {:ok, %Req.Response{status: 200, body: %{"data" => existing}}} ->
        desired_audiences = [zitadel_url]
        existing_audiences = Map.get(existing, "bound_audiences", [])

        unless existing_audiences == desired_audiences do
          Logger.warning("setup.role_drift",
            role: bao_role,
            reason: "bound_audiences mismatch — not auto-updating; manual review required"
          )
        end

      {:ok, %Req.Response{status: 404}} ->
        role_config = %{
          "bound_audiences" => [zitadel_url],
          "bound_claims" => %{"sub" => client_id},
          "token_policies" => [bao_policy],
          "user_claim" => "sub",
          "role_type" => "jwt"
        }

        role_config =
          if bao_issuer, do: Map.put(role_config, "bound_issuer", bao_issuer), else: role_config

        case Req.post("#{bao_addr}/v1/#{bao_jwt_mount}/role/#{bao_role}",
               json: role_config,
               headers: vault_header,
               receive_timeout: 5_000,
               connect_options: transport
             ) do
          {:ok, %Req.Response{status: s}} when s in [200, 204] ->
            :ok

          {:ok, %Req.Response{} = resp} ->
            step_error!(:openbao_role, resp)

          {:error, reason} ->
            step_error!(:openbao_role, reason)
        end

      {:ok, %Req.Response{} = resp} ->
        step_error!(:openbao_role, resp)

      {:error, reason} ->
        step_error!(:openbao_role, reason)
    end
  end

  defp ensure_openbao_secret do
    bao_addr = Application.fetch_env!(:auth_canary, :bao_addr)
    bao_secret_path = Application.fetch_env!(:auth_canary, :bao_secret_path)
    bao_kv_mount = Application.get_env(:auth_canary, :bao_kv_mount, "secret")
    bao_admin_token = Application.get_env(:auth_canary, :bao_admin_token)
    ca_cert = Application.get_env(:auth_canary, :bao_ca_cert)
    tls_verify = Application.get_env(:auth_canary, :bao_tls_verify, true)
    transport = [transport_opts: tls_opts(ca_cert, tls_verify)]
    vault_header = [{"x-vault-token", bao_admin_token || ""}]

    case Req.get("#{bao_addr}/v1/#{bao_kv_mount}/data/#{bao_secret_path}",
           headers: vault_header,
           receive_timeout: 5_000,
           connect_options: transport
         ) do
      {:ok, %Req.Response{status: 200}} ->
        :ok

      {:ok, %Req.Response{status: 404}} ->
        case Req.post("#{bao_addr}/v1/#{bao_kv_mount}/data/#{bao_secret_path}",
               json: %{"data" => %{"canary" => "health_check_ok"}},
               headers: vault_header,
               receive_timeout: 5_000,
               connect_options: transport
             ) do
          {:ok, %Req.Response{status: s}} when s in [200, 204] ->
            :ok

          {:ok, %Req.Response{} = resp} ->
            step_error!(:openbao_secret, resp)

          {:error, reason} ->
            step_error!(:openbao_secret, reason)
        end

      {:ok, %Req.Response{} = resp} ->
        step_error!(:openbao_secret, resp)

      {:error, reason} ->
        step_error!(:openbao_secret, reason)
    end
  end

  # --- Helpers ---

  defp step_error!(step, reason) do
    sanitized = Error.sanitize_reason(reason)
    Logger.error("setup.failure", step: step, reason: sanitized)
    raise "setup step #{step} failed: #{sanitized}"
  end

  defp tls_opts(ca_cert, true) when is_binary(ca_cert),
    do: [cacertfile: ca_cert, verify: :verify_peer]

  defp tls_opts(_ca_cert, true), do: [verify: :verify_peer]
  defp tls_opts(_ca_cert, false), do: [verify: :verify_none]
end
