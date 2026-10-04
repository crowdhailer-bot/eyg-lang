defmodule Mix.Tasks.AshEyg.Run do
  @shortdoc "Runs an EYG script against the domains of this application"
  @moduledoc """
  #{@shortdoc}.

      mix ash_eyg.run path/to/script.eyg
      mix ash_eyg.run -e 'perform SupportTicketRead({})'

  The script can perform every effect from `AshEyg.effects(otp_app: app)`.
  It runs without an actor, packages the script refers to are fetched from the hub.
  """
  use Mix.Task

  @impl true
  def run(args) do
    {source, app} = AshEyg.Mix.setup(args)

    # A one off run, packages the script refers to are fetched into an empty cache.
    {result, _cache} =
      AshEyg.run(source, AshEyg.empty_cache(), effects: AshEyg.effects(otp_app: app))

    case result do
      {:ok, value} -> Mix.shell().info(AshEyg.inspect(value))
      {:error, message} -> Mix.raise(message)
    end
  end
end
