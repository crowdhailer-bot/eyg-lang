defmodule Mix.Tasks.Compile.GleamLibraries do
  @moduledoc """
  Builds the EYG libraries listed in gleam/gleam.toml for Erlang, with Gleam,
  and copies their modules into ash_eyg.

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

defmodule AshEyg.MixProject do
  use Mix.Project

  def project do
    [
      app: :ash_eyg,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:gleam_libraries | Mix.compilers()],
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      # The hub client uses httpc
      extra_applications: [:logger, :crypto, :inets, :ssl]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ash, "~> 3.33"},
      {:spark, "~> 2.7"},
      {:simple_sat, "~> 0.1", only: :test}
    ]
  end
end
