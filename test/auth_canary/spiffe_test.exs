defmodule AuthCanary.SpiffeTest do
  use ExUnit.Case, async: false

  setup do
    prev_url = Application.get_env(:auth_canary, :zitadel_url)
    Application.put_env(:auth_canary, :zitadel_url, "https://test.example.com")

    on_exit(fn ->
      if prev_url do
        Application.put_env(:auth_canary, :zitadel_url, prev_url)
      else
        Application.delete_env(:auth_canary, :zitadel_url)
      end
    end)

    :ok
  end

  describe "fetch_jwt_svid/1" do
    test "returns {:error, _} when socket path does not exist" do
      socket = "/tmp/auth_canary_nonexistent_#{:rand.uniform(999_999)}.sock"
      assert {:error, _reason} = AuthCanary.Spiffe.fetch_jwt_svid(socket)
    end

    test "returns {:error, _} for an obviously invalid socket path" do
      assert {:error, _reason} = AuthCanary.Spiffe.fetch_jwt_svid("/tmp/definitely_no_socket.sock")
    end

    test "error reason is not a full JWT token string" do
      socket = "/tmp/auth_canary_nope_#{:rand.uniform(999_999)}.sock"
      assert {:error, reason} = AuthCanary.Spiffe.fetch_jwt_svid(socket)
      # The reason should not be a JWT token (eyJ...)
      reason_str = if is_binary(reason), do: reason, else: inspect(reason)
      refute String.starts_with?(reason_str, "eyJ") and String.contains?(reason_str, ".")
    end
  end
end
