defmodule AshEyg.Packages do
  @moduledoc """
  Loads the packages a script refers to, and their dependencies, from the EYG hub.

  The hub protocol, CID checks and dependency resolution are `eyg_hub`'s.
  This module supplies HTTP and hashing and drives the cache's actions until none are left.
  Nothing is preloaded, only the script's references decide what is fetched.

  The hub is `https://eyg.run` unless the `:hub` setting of `:ash_eyg` is set.
  The `:package_fetch` setting replaces HTTP, the tests use it to serve fixtures.
  """

  @cache :eyg@hub@cache
  @infer :eyg@analysis@inference@levels_j@contextual
  @type_debug :eyg@analysis@type_@binding@debug

  @doc "Load what the parsed script refers to, references that are already cached need no requests."
  def prepare(tree, cache) do
    references = :eyg@ir@tree.list_references(tree)

    case available(references, cache) do
      :ok ->
        {:ok, cache}

      {:error, _} ->
        url = Application.get_env(:ash_eyg, :hub, "https://eyg.run")

        case :ogre@origin.from_string(url) do
          {:ok, origin} ->
            fetch = Application.get_env(:ash_eyg, :package_fetch, &http/1)
            prepare(tree, cache, origin, fetch, &hash/2)

          {:error, _} ->
            {:error, "invalid hub origin"}
        end
    end
  end

  def prepare(tree, cache, origin, fetch, hash) do
    references = :eyg@ir@tree.list_references(tree)

    # prepare queues content and pinned modules and any missing release mappings.
    with {:ok, cache, trees} <- drain(@cache.prepare(cache, tree), origin, fetch, hash, []),
         # With the ledger available queue modules named by packages and versions,
         # cache.prepare does not queue these itself.
         {:ok, cache} <- queue(references, cache),
         {:ok, cache, trees} <- drain(cache, origin, fetch, hash, trees),
         :ok <- available(references, cache) do
      validate(trees, cache)
    end
  end

  defp queue(references, cache) do
    Enum.reduce_while(references, {:ok, cache}, fn reference, {:ok, cache} ->
      case module_cid(reference, cache) do
        {:ok, cid} -> {:cont, {:ok, @cache.fetch(cache, cid)}}
        error -> {:halt, error}
      end
    end)
  end

  defp module_cid({:content, cid}, _cache), do: {:ok, cid}

  defp module_cid({:package, name}, cache) do
    case @cache.package(cache, name) do
      {:ok, {:entry, _version, cid, _cursor, _sequence, _entry_cid}} -> {:ok, cid}
      {:error, nil} -> {:error, "package not found: " <> name}
    end
  end

  defp module_cid({:version, name, version} = reference, cache) do
    case @cache.unbound_release(cache, name, version) do
      {:ok, cid} -> {:ok, cid}
      {:error, nil} -> missing(reference)
    end
  end

  defp module_cid({:pinned, {:release, name, version, cid}} = reference, cache) do
    case @cache.unbound_release(cache, name, version) do
      {:ok, ^cid} -> {:ok, cid}
      _ -> missing(reference)
    end
  end

  defp module_cid({:relative, path}, _cache),
    do: {:error, "relative imports are not supported: " <> path}

  defp available(references, cache) do
    Enum.find_value(references, :ok, fn reference ->
      case @cache.get_reference(cache, reference) do
        {:ok, _module} -> nil
        {:error, nil} -> missing(reference)
      end
    end)
  end

  defp missing(reference),
    do: {:error, @type_debug.render_reason({:missing_reference, reference})}

  defp drain(cache, origin, fetch, hash, trees) do
    case @cache.flush(cache) do
      {cache, []} ->
        {:ok, cache, trees}

      {cache, actions} ->
        with {:ok, cache, trees} <- actions(actions, cache, origin, fetch, hash, trees),
             do: drain(cache, origin, fetch, hash, trees)
    end
  end

  defp actions([], cache, _origin, _fetch, _hash, trees), do: {:ok, cache, trees}

  defp actions([action | rest], cache, origin, fetch, hash, trees) do
    task = @cache.compute(action, origin, fetch, hash)

    case task.(fn result -> result end) do
      {:pull_packages_completed, {:error, reason}} ->
        {:error, describe(reason)}

      {:fetch_module_completed, _cid, {:error, reason}} ->
        {:error, describe(reason)}

      completed ->
        # Downloaded IR has no source, its locations are {0, 0}.
        {cache, resolved} = @cache.update(cache, completed, fn _ -> {0, 0} end)

        case for {_cid, {:error, reason}} <- resolved, do: reason do
          [reason | _] ->
            {:error, :eyg@interpreter@simple_debug.describe(reason)}

          [] ->
            trees =
              case completed do
                {:fetch_module_completed, _cid, {:ok, tree}} -> [tree | trees]
                _ -> trees
              end

            actions(rest, cache, origin, fetch, hash, trees)
        end
    end
  end

  # The cache infers module types but does not reject inference errors,
  # so every downloaded module is checked before scripts can use it.
  defp validate(trees, cache) do
    Enum.reduce_while(trees, {:ok, cache}, fn tree, ok ->
      analysis = @cache.infer_sync(@infer.check(@infer.pure(), tree), cache)

      case @infer.all_errors(analysis) do
        [] ->
          {:cont, ok}

        [{_meta, reason} | _] ->
          {:halt, {:error, "invalid package module: " <> @type_debug.render_reason(reason)}}
      end
    end)
  end

  defp describe(reason) when is_binary(reason), do: reason
  defp describe(reason), do: inspect(reason)

  # The hub's continuations take a callback for the result.
  defp http(request) do
    fn k ->
      case :gleam@httpc.send_bits(request) do
        {:ok, response} -> k.({:ok, response})
        {:error, reason} -> k.({:error, {:network_error, inspect(reason)}})
      end
    end
  end

  defp hash(algorithm, bytes), do: fn k -> k.(:gleam@crypto.hash(algorithm, bytes)) end
end
