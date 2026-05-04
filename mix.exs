defmodule AuthCanary.MixProject do
  use Mix.Project

  def project do
    [
      app: :auth_canary,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [
        auth_canary: [
          # Fixed cookie required so the COOKIE file is present in the nix store
          # output (mixRelease drops randomly-generated cookies). Not used for
          # distributed Erlang — auth_canary runs as a standalone node.
          cookie: "auth_canary_internal"
        ]
      ]
    ]
  end

  def application do
    [
      mod: {AuthCanary.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:spiffe_ex, github: "QuentinMallet/spiffe-ex", ref: "5b6034e5c4620c1ebe4ac6a590950660d3e460b7"},
      {:observlib, github: "ForgottenBeast/observlib-ex", ref: "f611dc2fd869675c4af806796c5afaadba4964ec", override: true},
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:stream_data, "~> 1.0", only: [:test, :dev], override: true},
      {:snabbkaffe, "~> 1.0", only: :test},
      {:mox, "~> 1.0", only: :test},
      {:plug, "~> 1.0", only: :test}
    ]
  end
end
