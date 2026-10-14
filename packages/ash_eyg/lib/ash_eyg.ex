defmodule AshEyg do
  @moduledoc """
  Expose Ash actions as typed EYG effects. Gleam loads, checks and runs scripts.
  The actor, tenant and context remain host values passed to each action.
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

  def empty_cache, do: :eyg@hub@cache.empty()

  def check(source, cache, opts),
    do:
      :ash_eyg@runtime.check(source, cache, AshEyg.Packages.loader(), opts).(&Function.identity/1)

  def run(source, cache, opts),
    do: :ash_eyg@runtime.run(source, cache, AshEyg.Packages.loader(), opts).(&Function.identity/1)

  def inspect(value), do: :eyg@embedding@runtime.inspect(value)
end
