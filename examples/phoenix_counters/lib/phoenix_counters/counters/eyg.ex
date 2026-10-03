defmodule PhoenixCounters.Counters.Eyg do
  @moduledoc """
  Check and run EYG scripts that can use only the counters effects.

  Both functions take a package cache and return `{result, cache}`, on success and on error.
  The caller keeps the cache, see `PhoenixCounters.Scripts`.
  """

  alias PhoenixCounters.Counters.{Effects, Packages}

  @cache :eyg@hub@cache
  @infer :eyg@analysis@inference@levels_j@contextual
  @type_debug :eyg@analysis@type_@binding@debug
  @value_debug :eyg@interpreter@simple_debug
  @expression :eyg@interpreter@expression

  @doc "Parse a script without loading or checking it."
  def parse(source) do
    case :eyg@parser.all_from_string(source) do
      {:ok, _tree} -> :ok
      {:error, reason} -> {:error, :eyg@parser.format_error(reason, source)}
    end
  end

  @doc "Load the script's packages and type check it, returns `{{:ok, type} | {:error, message}, cache}`."
  def check(source, cache) do
    case parse_and_check(source, cache) do
      {{:ok, {_tree, analysis}}, cache} ->
        {{:ok, @type_debug.render_type(@infer.type_(analysis))}, cache}

      failed ->
        failed
    end
  end

  @doc "Check the script then run it, returns `{{:ok, value} | {:error, message}, cache}`."
  def run(source, cache) do
    case parse_and_check(source, cache) do
      {{:ok, {tree, _analysis}}, cache} ->
        {run_step(@expression.execute(tree, []), source, cache), cache}

      failed ->
        failed
    end
  end

  @doc "Render an EYG value as EYG source."
  def inspect_value(value), do: @value_debug.inspect(value)

  # static_loop answers references from the cache, only effects reach the handler.
  defp run_step(step, source, cache) do
    case @cache.static_loop(step, cache, &@expression.resume/3) do
      {:error, {{:unhandled_effect, label, lift}, _span, env, k}} ->
        reply = Effects.handle(label, lift)
        run_step(@expression.resume(reply, env, k), source, cache)

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

  defp parse_and_check(source, cache) do
    case :eyg@parser.all_from_string(source) do
      {:error, reason} ->
        {{:error, :eyg@parser.format_error(reason, source)}, cache}

      {:ok, tree} ->
        case Packages.prepare(tree, cache) do
          {:ok, loaded} -> {analyse(tree, source, loaded), loaded}
          # A failed batch was not validated, keep the caller's cache.
          error -> {error, cache}
        end
    end
  end

  defp analyse(tree, source, cache) do
    context = @infer.with_effects(@infer.pure(), Effects.types())
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
