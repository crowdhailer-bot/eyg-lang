defmodule AshEyg do
  @moduledoc """
  Run EYG programs against your Ash domains.

  Every action of a resource that uses `AshEyg.Resource`, in a domain that uses `AshEyg.Domain`,
  is an effect. Programs are type checked against the effects they are given before they run.

      effects = AshEyg.effects(otp_app: :helpdesk)

      {result, cache} =
        AshEyg.run(~s|perform SupportTicketOpen({subject: "Printer on fire"})|, AshEyg.empty_cache(),
          effects: effects,
          actor: current_user
        )

  Packages a program refers to, such as `@standard`, are fetched from the hub into the cache.
  `check/3` and `run/3` return the cache on success and on error, keep it for the next call.
  `AshEyg.Session` is a process that does this.

  The actor, tenant and context are given to every action a program calls.
  A program cannot read or change them.
  """

  alias AshEyg.{Effect, Packages}

  @cache :eyg@hub@cache
  @infer :eyg@analysis@inference@levels_j@contextual
  @type_debug :eyg@analysis@type_@binding@debug
  @value_debug :eyg@interpreter@simple_debug
  @expression :eyg@interpreter@expression

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

  @doc "A cache with no packages."
  def empty_cache, do: @cache.empty()

  @doc """
  Load the packages a program refers to and type check it against the effects.

  Returns `{{:ok, type} | {:error, message}, cache}`, errors are rendered against the source.

  ## Options

    * `:effects` - required, the effects the program may perform.
  """
  def check(source, cache, opts) do
    case parse_and_check(source, cache, opts) do
      {{:ok, {_tree, analysis}}, cache} ->
        {{:ok, @type_debug.render_type(@infer.type_(analysis))}, cache}

      failed ->
        failed
    end
  end

  @doc """
  Check a program then run it.

  Returns `{{:ok, value} | {:error, message}, cache}` where the value is an EYG value, see `inspect/1`.

  ## Options

  As `check/3`, and

    * `:actor`, `:tenant`, `:context` - given to every action the program calls.
  """
  def run(source, cache, opts) do
    case parse_and_check(source, cache, opts) do
      {{:ok, {tree, _analysis}}, cache} ->
        effects = Map.new(Keyword.fetch!(opts, :effects), &{&1.label, &1})
        ash_opts = Keyword.take(opts, [:actor, :tenant, :context])
        {run_step(@expression.execute(tree, []), source, cache, effects, ash_opts), cache}

      failed ->
        failed
    end
  end

  @doc "Render an EYG value as EYG source."
  def inspect(value), do: @value_debug.inspect(value)

  # static_loop answers references from the cache, only effects reach the handlers.
  defp run_step(step, source, cache, effects, ash_opts) do
    case @cache.static_loop(step, cache, &@expression.resume/3) do
      {:error, {{:unhandled_effect, label, lift}, _span, env, k}} ->
        %Effect{handle: handle} = Map.fetch!(effects, label)
        reply = handle.(lift, ash_opts)
        run_step(@expression.resume(reply, env, k), source, cache, effects, ash_opts)

      {:error, {reason, span, _env, _k}} ->
        {:error,
         :eyg@parser.render_error(
           @value_debug.describe(reason),
           @value_debug.hint(reason),
           source,
           span
         )}

      {:ok, value} ->
        {:ok, value}
    end
  end

  defp parse_and_check(source, cache, opts) do
    case :eyg@parser.all_from_string(source) do
      {:error, reason} ->
        {{:error, :eyg@parser.format_error(reason, source)}, cache}

      {:ok, tree} ->
        case Packages.prepare(tree, cache) do
          {:ok, loaded} -> {analyse(tree, source, loaded, opts), loaded}
          # A failed batch was not validated, keep the caller's cache.
          error -> {error, cache}
        end
    end
  end

  defp analyse(tree, source, cache, opts) do
    signatures = Enum.map(Keyword.fetch!(opts, :effects), &{&1.label, {&1.lift, &1.lower}})
    context = @infer.with_effects(@infer.pure(), signatures)
    analysis = @cache.infer_sync(@infer.check(context, tree), cache)

    case @infer.all_errors(analysis) do
      [] ->
        {:ok, {tree, analysis}}

      errors ->
        errors
        |> Enum.map(fn {span, reason} ->
          :eyg@parser.render_error(
            @type_debug.render_reason(reason),
            @type_debug.hint(reason),
            source,
            span
          )
        end)
        |> Enum.join("\n\n")
        |> then(&{:error, &1})
    end
  end
end
