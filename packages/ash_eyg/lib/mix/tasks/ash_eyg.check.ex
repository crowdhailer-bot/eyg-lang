defmodule Mix.Tasks.AshEyg.Check do
  @shortdoc "Check an EYG script against this application's effects"
  use Mix.Task
  @impl true
  def run(args) do
    AshEyg.Mix.start()
    :ash_eyg@tools.check(args).(&Function.identity/1) |> AshEyg.Mix.report()
  end
end
