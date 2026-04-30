defmodule AuthCanary.Openbao do
  require Logger

  @doc "Authenticate via OpenBao JWT auth mount and read KV v2 secret"
  def read_secret(oidc_token) do
    bao_addr = Application.fetch_env!(:auth_canary, :bao_addr)
    bao_role = Application.fetch_env!(:auth_canary, :bao_role)
    bao_secret_path = Application.fetch_env!(:auth_canary, :bao_secret_path)
    bao_kv_mount = Application.get_env(:auth_canary, :bao_kv_mount, "secret")
    bao_jwt_mount = Application.get_env(:auth_canary, :bao_jwt_mount, "auth/jwt")
    ca_cert = Application.get_env(:auth_canary, :bao_ca_cert)
    tls_verify = Application.get_env(:auth_canary, :bao_tls_verify, true)
    transport = [transport_opts: tls_opts(ca_cert, tls_verify)]

    with {:ok, client_token} <-
           authenticate(bao_addr, bao_jwt_mount, bao_role, oidc_token, transport),
         {:ok, secret} <-
           read_kv_secret(bao_addr, bao_kv_mount, bao_secret_path, client_token, transport) do
      {:ok, secret}
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
