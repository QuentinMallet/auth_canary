defmodule AuthCanary.Spiffe do
  require Logger

  @doc "Fetch JWT SVID from SPIRE Workload API via spiffe-ex gRPC adapter (fresh each call)"
  def fetch_jwt_svid(socket_path) do
    audience = Application.fetch_env!(:auth_canary, :zitadel_url)

    case SpiffeEx.WorkloadAPI.GrpcAdapter.fetch_jwt_svid(socket_path, [audience]) do
      {:ok, %SpiffeEx.SVID{token: token}} -> {:ok, token}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  catch
    kind, value -> {:error, "#{kind}: #{inspect(value)}"}
  end
end
