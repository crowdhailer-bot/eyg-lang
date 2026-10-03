defmodule Mix.Tasks.Compile.GleamLibraries do
  @moduledoc """
  Builds the EYG libraries listed in gleam/gleam.toml for Erlang, with Gleam,
  and copies their modules into this application.

  The EYG packages are not published for Erlang, so Mix cannot fetch them.
  """
  use Mix.Task.Compiler

  @impl true
  def run(_args) do
    # Gleam needs a source directory, the project has no source of its own.
    File.mkdir_p!("gleam/src")

    case System.cmd("gleam", ["build", "--target", "erlang"], cd: "gleam", stderr_to_stdout: true) do
      {_output, 0} ->
        ebin = Mix.Project.compile_path()
        File.mkdir_p!(ebin)

        for beam <- Path.wildcard("gleam/build/dev/erlang/*/ebin/*.beam") do
          File.cp!(beam, Path.join(ebin, Path.basename(beam)))
        end

        {:ok, []}

      {output, _status} ->
        Mix.shell().error(output)
        {:error, []}
    end
  end
end

defmodule PhoenixCounters.MixProject do
  use Mix.Project

  def project do
    [
      app: :phoenix_counters,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:gleam_libraries, :phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {PhoenixCounters.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.15"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:daisyui,
       github: "saadeghi/daisyui",
       tag: "v5.5.20",
       sparse: "packages/bundle",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind phoenix_counters", "esbuild phoenix_counters"],
      "assets.deploy": [
        "tailwind phoenix_counters --minify",
        "esbuild phoenix_counters --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
