defmodule Trivium.MixProject do
  use Mix.Project

  def project do
    [
      app: :trivium,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Trivium.Application, []}
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:optimus, "~> 0.2"},
      {:mox, "~> 1.2", only: :test}
    ]
  end

  defp escript do
    [main_module: Trivium.CLI, name: "trivium"]
  end
end
