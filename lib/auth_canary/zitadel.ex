defmodule AuthCanary.Zitadel do
  require Logger

  @doc "Exchange JWT SVID for Zitadel OIDC token via RFC 7523 JWT Bearer assertion"
  def exchange_token(jwt_svid) do
    url = Application.fetch_env!(:auth_canary, :zitadel_url)
    ca_cert = Application.get_env(:auth_canary, :zitadel_ca_cert)
    tls_verify = Application.get_env(:auth_canary, :zitadel_tls_verify, true)

    body = %{
      "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
      "client_assertion_type" => "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
      "client_assertion" => jwt_svid,
      "scope" => "openid"
    }

    case Req.post("#{url}/oauth/v2/token",
           form: body,
           receive_timeout: 5_000,
           connect_options: [transport_opts: tls_opts(ca_cert, tls_verify)]
         ) do
      {:ok, %Req.Response{status: 200, body: %{"access_token" => token}}} ->
        {:ok, token}

      {:ok, %Req.Response{} = resp} ->
        {:error, resp}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, e}
  end

  defp tls_opts(ca_cert, true) when is_binary(ca_cert),
    do: [cacertfile: ca_cert, verify: :verify_peer]

  defp tls_opts(_ca_cert, true), do: [verify: :verify_peer]
  defp tls_opts(_ca_cert, false), do: [verify: :verify_none]
end
