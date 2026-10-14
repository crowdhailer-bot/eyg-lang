defmodule Mix.Tasks.Compile.HelpdeskGleam do
  use Mix.Task.Compiler
  @impl true
  def run(_args) do
    destination = Path.expand(Mix.Project.compile_path())

    case System.cmd("gleam", ["run", "-m", "eyg/embedding/install_beams", "--", destination],
           cd: "gleam",
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        {:ok, []}

      {output, _} ->
        Mix.shell().error(output)
        {:error, []}
    end
  end
end

defmodule Helpdesk.MixProject do
  use Mix.Project

  def project do
    [
      app: :helpdesk,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: [:helpdesk_gleam | Mix.compilers()],
      consolidate_protocols: Mix.env() != :dev,
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Helpdesk.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      "assets.build": ["compile", "eyg.assets"]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:sourceror, "~> 1.8", only: [:dev, :test]},
      {:ash, ">= 3.34.6 and < 4.0.0"},
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
