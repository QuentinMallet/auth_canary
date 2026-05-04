defmodule AuthCanary.PipelineZitadel do
  @moduledoc "Zitadel OIDC -> OpenBao auth/jwt -> KV secret pipeline check."

  alias AuthCanary.{Zitadel, Openbao, Error}

  @spec run() :: {:ok, :success} | {:error, atom(), String.t()}
  def run do
    with {:ok, token} <- wrap_step(:zitadel, fn -> Zitadel.fetch_access_token() end),
         {:ok, _secret} <- wrap_step(:openbao, fn -> Openbao.read_secret_via_oidc(token) end) do
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
