defmodule AuthCanary.PipelineE2ETest do
  use ExUnit.Case, async: false

  @moduletag :e2e
  @moduletag timeout: 30_000

  test "full pipeline: SPIFFE SVID → Zitadel token → OpenBao token → KV secret" do
    assert {:ok, secret} = AuthCanary.PipelineSpire.run()
    assert is_map(secret)
    assert Map.has_key?(secret, "value")
  end

  test "pipeline returns error on invalid BAO_SECRET_PATH" do
    original = System.get_env("BAO_SECRET_PATH")
    System.put_env("BAO_SECRET_PATH", "nonexistent/path/that/does/not/exist")
    on_exit(fn -> System.put_env("BAO_SECRET_PATH", original || "") end)
    assert {:error, _} = AuthCanary.PipelineSpire.run()
  end
end
