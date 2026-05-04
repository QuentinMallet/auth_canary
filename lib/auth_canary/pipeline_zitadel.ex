defmodule AuthCanary.PipelineZitadel do
  @moduledoc "Zitadel OIDC -> OpenBao auth/jwt -> KV secret pipeline check."

  alias AuthCanary.{Zitadel, Openbao, Error}

  @spec run() :: {:ok, :success} | {:error, atom(), String.t()}
  def run do
    with {:ok, token} <- Error.wrap_step(:zitadel, fn -> Zitadel.fetch_access_token() end),
         {:ok, _secret} <- Error.wrap_step(:openbao, fn -> Openbao.read_secret_via_oidc(token) end) do
      {:ok, :success}
    end
  end
end
