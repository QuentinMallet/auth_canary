defmodule AuthCanary.Openbao do
  require Logger

  @doc "Authenticate via OpenBao JWT auth mount (SPIRE leg) and read KV v2 secret. Backward-compatible alias."
  def read_secret(jwt_svid), do: read_secret_via_spire(jwt_svid)

  @doc "SPIRE leg: authenticate via auth/jwt-spire and read KV v2 secret"
  def read_secret_via_spire(jwt_svid) do
    bao_addr = Application.fetch_env!(:auth_canary, :bao_addr)
    bao_role = Application.fetch_env!(:auth_canary, :bao_role)
    bao_secret_path = Application.fetch_env!(:auth_canary, :bao_secret_path)
    bao_kv_mount = Application.get_env(:auth_canary, :bao_kv_mount, "secret")
    bao_jwt_mount = Application.get_env(:auth_canary, :bao_jwt_mount, "auth/jwt-spire")
    ca_cert = Application.get_env(:auth_canary, :bao_ca_cert)
    tls_verify = Application.get_env(:auth_canary, :bao_tls_verify, true)
    transport = [transport_opts: tls_opts(ca_cert, tls_verify)]

    with {:ok, client_token} <-
           authenticate(bao_addr, bao_jwt_mount, bao_role, jwt_svid, transport),
         {:ok, secret} <-
           read_kv_secret(bao_addr, bao_kv_mount, bao_secret_path, client_token, transport) do
      {:ok, secret}
    end
  rescue
    e -> {:error, e}
  end

  @doc "Zitadel leg: authenticate via auth/jwt (Zitadel OIDC) and read KV v2 secret"
  def read_secret_via_oidc(access_token) do
    bao_addr = Application.fetch_env!(:auth_canary, :bao_addr)
    bao_role = Application.get_env(:auth_canary, :bao_zitadel_role)
    bao_secret_path = Application.get_env(:auth_canary, :bao_zitadel_secret_path)
    bao_kv_mount = Application.get_env(:auth_canary, :bao_kv_mount, "secret")
    bao_jwt_mount = Application.get_env(:auth_canary, :bao_zitadel_jwt_mount, "auth/jwt")
    ca_cert = Application.get_env(:auth_canary, :bao_ca_cert)
    tls_verify = Application.get_env(:auth_canary, :bao_tls_verify, true)
    transport = [transport_opts: tls_opts(ca_cert, tls_verify)]

    if is_nil(bao_role) or is_nil(bao_secret_path) do
      {:error, :not_configured}
    else
      with {:ok, client_token} <-
             authenticate(bao_addr, bao_jwt_mount, bao_role, access_token, transport),
           {:ok, secret} <-
             read_kv_secret(bao_addr, bao_kv_mount, bao_secret_path, client_token, transport) do
        {:ok, secret}
      end
    end
  rescue
    e -> {:error, e}
  end

  defp authenticate(addr, jwt_mount, role, jwt, transport) do
    case Req.post("#{addr}/v1/#{jwt_mount}/login",
           json: %{"role" => role, "jwt" => jwt},
           receive_timeout: 5_000,
           connect_options: transport
         ) do
      {:ok, %Req.Response{status: 200, body: %{"auth" => %{"client_token" => token}}}} ->
        {:ok, token}

      {:ok, %Req.Response{} = resp} ->
        {:error, resp}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_kv_secret(addr, kv_mount, secret_path, client_token, transport) do
    case Req.get("#{addr}/v1/#{kv_mount}/data/#{secret_path}",
           headers: [{"x-vault-token", client_token}],
           receive_timeout: 5_000,
           connect_options: transport
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{} = resp} ->
        {:error, resp}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp tls_opts(ca_cert, true) when is_binary(ca_cert),
    do: [cacertfile: ca_cert, verify: :verify_peer]

  defp tls_opts(_ca_cert, true), do: [verify: :verify_peer]
  defp tls_opts(_ca_cert, false), do: [verify: :verify_none]
end
