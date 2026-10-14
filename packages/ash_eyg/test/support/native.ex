defmodule AshEyg.Test.Native do
  @moduledoc false
  def effects, do: AshEyg.effects(domains: [AshEyg.Test.Support])
  def named, do: AshEyg.effects(domains: [AshEyg.Test.Named])
  def label(effect), do: effect.label
  def action(effect), do: to_string(effect.action)
  def check(source, cache, effects), do: AshEyg.check(source, cache, effects: effects)

  def run(source, cache, effects, actor),
    do:
      AshEyg.run(source, cache,
        effects: effects,
        actor: actor,
        tenant: "tenant-a",
        context: %{marker: "context-a"}
      )

  def admin, do: %{id: "admin"}
  def no_actor, do: nil

  def option(effects),
    do: [effects: effects, actor: admin(), tenant: "tenant-a", context: %{marker: "context-a"}]

  def session, do: AshEyg.Session.start_link([])
  def stop(pid), do: GenServer.stop(pid)
  def check_session(pid, source, effects), do: AshEyg.Session.check(pid, source, effects: effects)

  def run_session(pid, source, effects),
    do: AshEyg.Session.run(pid, source, effects: effects, actor: admin())

  def generic(source, actor) do
    AshEyg.Test.Scripts.Script
    |> Ash.ActionInput.for_action(:run, %{source: source},
      actor: actor,
      tenant: "tenant-a",
      context: %{marker: "context-a"}
    )
    |> Ash.run_action()
  end

  def invalid_argument(%Ash.Error.Invalid{errors: [error]}),
    do: {to_string(error.field), error.message}

  def fixture(fetch), do: Application.put_env(:ash_eyg, :package_fetch, fetch)
  def clear_fixture, do: Application.delete_env(:ash_eyg, :package_fetch)

  def context_field(value, key) when is_map(value),
    do: Map.get(value, String.to_existing_atom(key))

  def context_field(_value, _key), do: nil
  def raw(value), do: value

  def host_effect({:effect, label, lift, lower, handle}),
    do: AshEyg.Effect.new(label, lift, lower, handle)
end
