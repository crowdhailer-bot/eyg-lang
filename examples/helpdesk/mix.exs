defmodule Helpdesk.MixProject do
  use Mix.Project

  def project do
    [
      app: :helpdesk,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      consolidate_protocols: Mix.env() != :dev
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Helpdesk.Application, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:sourceror, "~> 1.8", only: [:dev, :test]},
      {:ash, "~> 3.0"},
      {:ash_eyg, path: "../../packages/ash_eyg"},
      {:ash_admin, "~> 1.3"},
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.1"},
      {:bandit, "~> 1.5"},
      {:igniter, "~> 0.6", only: [:dev, :test]}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
