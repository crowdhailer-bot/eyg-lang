defmodule AshEyg.RunScript do
  @moduledoc """
  A generic action that runs the EYG script in its `source` argument.

  Any interface that can call a generic action can run scripts, for example AshAdmin.

      action :run, :string do
        argument :source, :string, allow_nil?: false
        run {AshEyg.RunScript, otp_app: :helpdesk, packages: %{"standard" => path}}
      end

  The script can perform every effect of the application, as the actor and tenant of the action.
  The action returns the value of the script rendered as EYG.
  Type errors are an invalid `source` argument.

  ## Options

    * `:otp_app` - required, the application whose domains are exposed.
    * `:packages` - a map of name to the path of an IR JSON file, for `@name` references.
  """
  use Ash.Resource.Actions.Implementation

  @impl true
  def run(input, opts, context) do
    packages =
      Map.new(Keyword.get(opts, :packages, %{}), fn {name, path} ->
        {:ok, package} = AshEyg.load_package(path)
        {name, package}
      end)

    run_opts = [
      effects: AshEyg.effects(otp_app: Keyword.fetch!(opts, :otp_app)),
      packages: packages,
      actor: context.actor,
      tenant: context.tenant
    ]

    case AshEyg.run(input.arguments.source, run_opts) do
      {:ok, value} ->
        {:ok, AshEyg.inspect(value)}

      {:error, message} ->
        {:error, Ash.Error.Action.InvalidArgument.exception(field: :source, message: message)}
    end
  end
end
