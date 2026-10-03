defmodule Mix.Tasks.AshEyg.Effects do
  @shortdoc "Lists the EYG effects for the actions of this application"
  @moduledoc """
  #{@shortdoc}, with the type each effect lifts and the type of its reply.

      mix ash_eyg.effects
  """
  use Mix.Task

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    for effect <- AshEyg.effects(otp_app: Mix.Project.config()[:app]) do
      Mix.shell().info("""
      #{effect.label}
        lift:  #{indent(:eyg@analysis@type_@binding@debug.render_type(effect.lift))}
        reply: #{indent(:eyg@analysis@type_@binding@debug.render_type(effect.lower))}
      """)
    end
  end

  defp indent(text), do: String.replace(text, "\n", "\n         ")
end
