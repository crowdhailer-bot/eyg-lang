defmodule AshEyg do
  @moduledoc """
  Run EYG programs against your Ash domains.

  Every action of a resource that uses `AshEyg.Resource`, in a domain that uses `AshEyg.Domain`,
  is an effect. Programs are type checked against the effects they are given before they run.

      effects = AshEyg.effects(otp_app: :helpdesk)

      AshEyg.run(~s|perform SupportTicketOpen({subject: "Printer on fire"})|,
        effects: effects,
        actor: current_user
      )

  The actor, tenant and context are given to every action a program calls.
  A program cannot read or change them.
  """

  alias AshEyg.Effect

  @doc """
  The effects for the actions of exposed resources.

  Pass `otp_app:` for every domain configured in `:ash_domains`, or `domains:` for a list.
  The result is a list, keep only the effects a program should have.

      AshEyg.effects(otp_app: :helpdesk)
      |> Enum.filter(&(&1.resource == Helpdesk.Support.Ticket and &1.action in [:read, :open]))
  """
  def effects(opts) do
    domains =
      case Keyword.fetch(opts, :domains) do
        {:ok, domains} -> domains
        :error -> Ash.Info.domains(Keyword.fetch!(opts, :otp_app))
      end

    for domain <- domains,
        AshEyg.Domain in Spark.extensions(domain),
        effect <- AshEyg.Actions.effects(domain),
        do: effect
  end

  @doc """
  Type check a program against the effects.

  Returns `{:ok, type}` or `{:error, message}` with every error rendered against the source.

  ## Options

    * `:effects` - required, the effects the program may perform.
    * `:packages` - a map of name to package for `@name` references, see `:eyg_beam.load_package/1`.
  """
  def check(source, opts) do
    :eyg_beam.check(source, signatures(opts), Keyword.get(opts, :packages, %{}))
  end

  @doc """
  Type check a program then run it.

  Returns `{:ok, value}` where the value is an EYG value, see `inspect/1`, or `{:error, message}`.

  ## Options

  As `check/2`, and

    * `:actor`, `:tenant`, `:context` - given to every action the program calls.
  """
  def run(source, opts) do
    effects = Map.new(Keyword.fetch!(opts, :effects), &{&1.label, &1})
    ash_opts = Keyword.take(opts, [:actor, :tenant, :context])

    handler = fn label, lift ->
      %Effect{handle: handle} = Map.fetch!(effects, label)
      handle.(lift, ash_opts)
    end

    :eyg_beam.run(source, signatures(opts), Keyword.get(opts, :packages, %{}), handler)
  end

  @doc """
  Load a package from the path of its IR JSON file, for the `:packages` option.

  Packages are evaluated and type checked once, then cached.

      {:ok, standard} = AshEyg.load_package("eyg_packages/standard/index.eyg.json")
      AshEyg.run(source, effects: effects, packages: %{"standard" => standard})
  """
  def load_package(path) do
    key = {__MODULE__, :package, Path.expand(path)}

    case :persistent_term.get(key, nil) do
      nil ->
        with {:ok, json} <- File.read(path),
             {:ok, package} <- :eyg_beam.load_package(json) do
          :persistent_term.put(key, package)
          {:ok, package}
        end

      package ->
        {:ok, package}
    end
  end

  @doc "Render an EYG value as EYG source."
  def inspect(value), do: :eyg_beam.inspect(value)

  defp signatures(opts) do
    opts
    |> Keyword.fetch!(:effects)
    |> Enum.map(&{&1.label, {&1.lift, &1.lower}})
  end
end
