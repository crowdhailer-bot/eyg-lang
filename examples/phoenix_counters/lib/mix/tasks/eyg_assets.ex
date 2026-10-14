defmodule Mix.Tasks.Eyg.Assets do
  @moduledoc "Build the Gleam editor and browser library bindings."
  use Mix.Task

  def run(_args) do
    case System.cmd("gleam", ["run", "-m", "bundle"], cd: "browser", stderr_to_stdout: true) do
      {output, 0} -> Mix.shell().info(output)
      {output, _} -> Mix.raise(output)
    end
  end
end
