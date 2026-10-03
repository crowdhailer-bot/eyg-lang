defmodule AshEyg.MixProject do
  use Mix.Project

  def project do
    [
      app: :ash_eyg,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ash, "~> 3.33"},
      {:spark, "~> 2.7"},
      {:eyg_beam, path: "../eyg_beam"},
      {:simple_sat, "~> 0.1", only: :test}
    ]
  end
end
