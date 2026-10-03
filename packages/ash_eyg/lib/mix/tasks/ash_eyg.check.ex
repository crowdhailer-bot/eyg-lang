defmodule Mix.Tasks.AshEyg.Check do
  @shortdoc "Type checks an EYG script against the domains of this application"
  @moduledoc """
  #{@shortdoc}.

      mix ash_eyg.check path/to/script.eyg
      mix ash_eyg.check -e 'perform SupportTicketRead({})'

  Prints the type of the script or every type error.
  """
  use Mix.Task

  @impl true
  def run(args) do
    {source, app} = AshEyg.Mix.setup(args)

    case AshEyg.check(source, effects: AshEyg.effects(otp_app: app)) do
      {:ok, type} -> Mix.shell().info(type)
      {:error, message} -> Mix.raise(message)
    end
  end
end
