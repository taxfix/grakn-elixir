defmodule GraknElixir.MixProject do
  use Mix.Project

  def project do
    [
      app: :grakn_elixir,
      version: "0.1.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:db_connection, "~> 1.1.0"},
      {:grpc, "~> 0.3.1"},
      {:cowlib, "~> 2.4.0", override: true},
      {:protobuf, "~> 0.5.3"},
      {:ex_doc, ">= 0.0.0", only: :dev},
      {:earmark, ">= 0.0.0", only: :dev},
      {:dialyxir, "~> 0.5.1", only: :dev},
      {:benchee, "~> 0.13", only: :dev}
    ]
  end
end
