defmodule AshEyg.Mix do
  @moduledoc false
  def start, do: Mix.Task.run("app.start")
  def options, do: [effects: AshEyg.effects(otp_app: Mix.Project.config()[:app])]
  def effects, do: options() |> Keyword.fetch!(:effects) |> Enum.map(&AshEyg.Native.effect/1)
  def report({:ok, text}), do: Mix.shell().info(text)
  def report({:error, message}), do: Mix.raise(message)
end
