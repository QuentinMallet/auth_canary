defmodule AuthCanary.MixProject do
  use Mix.Project

  def project do
    [
      app: :auth_canary,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      {:spiffe_ex, github: "QuentinMallet/spiffe-ex", ref: "093352d98152718f9b5060c6c1e4fe3533c916f9"},
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
