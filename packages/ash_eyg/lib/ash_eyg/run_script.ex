defmodule AshEyg.RunScript do
  @moduledoc """
  A generic action that runs the EYG script in its `source` argument.

  Any interface that can call a generic action can run scripts, for example AshAdmin.

      action :run, :string do
        argument :source, :string, allow_nil?: false
        run {AshEyg.RunScript, otp_app: :helpdesk, session: Helpdesk.Scripts}
      end

  The script can perform every effect of the application, as the actor and tenant of the action.
  Packages it refers to are fetched from the hub.
  The action returns the value of the script rendered as EYG.
  Type errors are an invalid `source` argument.

  ## Options

    * `:otp_app` - required, the application whose domains are exposed.
    * `:session` - an `AshEyg.Session` that keeps fetched packages between runs.
      Without one every run starts with an empty cache.
  """
  use Ash.Resource.Actions.Implementation

  @impl true
  def run(input, opts, context) do
    source = input.arguments.source

    run_opts = [
      effects: AshEyg.effects(otp_app: Keyword.fetch!(opts, :otp_app)),
      actor: context.actor,
      tenant: context.tenant
    ]

    result =
      case Keyword.fetch(opts, :session) do
        {:ok, session} -> AshEyg.Session.run(session, source, run_opts)
        :error -> source |> AshEyg.run(AshEyg.empty_cache(), run_opts) |> elem(0)
      end

    case result do
      {:ok, value} ->
        {:ok, AshEyg.inspect(value)}

      {:error, message} ->
        {:error, Ash.Error.Action.InvalidArgument.exception(field: :source, message: message)}
    end
  end
end
