defmodule AuthCanary.Zitadel do
  @moduledoc """
  Fetches a Zitadel access token via OAuth2 client_credentials grant.

  Config keys (all optional — returns {:error, :not_configured} if absent):
    :zitadel_addr          — Zitadel base URL (e.g. https://zitadel.example.com)
    :zitadel_client_id     — OAuth2 client ID
    :zitadel_client_secret — OAuth2 client secret
  """

  def fetch_access_token do
    addr = Application.get_env(:auth_canary, :zitadel_addr)
    id = Application.get_env(:auth_canary, :zitadel_client_id)
    secret = Application.get_env(:auth_canary, :zitadel_client_secret)

    if is_nil(addr) or is_nil(id) or is_nil(secret) do
      {:error, :not_configured}
    else
      do_fetch(addr, id, secret)
    end
  end

  defp do_fetch(addr, client_id, client_secret) do
    url = "#{addr}/oauth/v2/token"

    body =
      URI.encode_query(%{
        "grant_type" => "client_credentials",
        "client_id" => client_id,
        "client_secret" => client_secret,
        "scope" => "openid"
      })

    headers = [{"content-type", "application/x-www-form-urlencoded"}]

    case Req.post(url, body: body, headers: headers) do
      {:ok, %{status: 200, body: %{"access_token" => token}}} ->
        {:ok, token}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end
end
