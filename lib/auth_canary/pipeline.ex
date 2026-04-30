defmodule AuthCanary.Pipeline do
  alias AuthCanary.{Spiffe, Zitadel, Openbao, Error}

  @spec run() :: {:ok, :success} | {:error, atom(), String.t()}
  def run do
    spiffe_socket = Application.fetch_env!(:auth_canary, :spiffe_socket)

    with {:ok, jwt_svid} <- wrap_step(:spiffe, fn -> Spiffe.fetch_jwt_svid(spiffe_socket) end),
         {:ok, oidc_token} <- wrap_step(:zitadel, fn -> Zitadel.exchange_token(jwt_svid) end),
         {:ok, _secret} <- wrap_step(:openbao, fn -> Openbao.read_secret(oidc_token) end) do
      {:ok, :success}
    end
  end

  defp wrap_step(step, fun) do
    case fun.() do
      {:ok, _} = ok -> ok
      {:error, reason} -> {:error, step, sanitize_reason(reason)}
      other -> {:error, step, sanitize_reason(other)}
    end
  rescue
    e -> {:error, :unknown, sanitize_reason(e)}
  catch
    kind, value -> {:error, :unknown, sanitize_reason({kind, value})}
  end

  defp sanitize_reason(reason), do: Error.sanitize_reason(reason)
end
