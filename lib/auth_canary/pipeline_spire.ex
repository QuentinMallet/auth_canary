defmodule AuthCanary.PipelineSpire do
  @moduledoc "SPIRE JWT SVID -> OpenBao auth/jwt-spire -> KV secret pipeline check."

  alias AuthCanary.{Spiffe, Openbao, Error}

  @spec run() :: {:ok, :success} | {:error, atom(), String.t()}
  def run do
    spiffe_socket = Application.fetch_env!(:auth_canary, :spiffe_socket)

    with {:ok, jwt_svid} <- Error.wrap_step(:spiffe, fn -> Spiffe.fetch_jwt_svid(spiffe_socket) end),
         {:ok, _secret} <- Error.wrap_step(:openbao, fn -> Openbao.read_secret_via_spire(jwt_svid) end) do
      {:ok, :success}
    end
  end
end
