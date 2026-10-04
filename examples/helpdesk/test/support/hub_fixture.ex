defmodule Helpdesk.HubFixture do
  @moduledoc """
  Serves packages with the hub's own codecs, without a network.

  Every request is sent to the process that built the fetch function as `{:hub_request, url}`.
  """

  @doc "The standard library from this repository."
  def standard do
    {:ok, json} = File.read("../../eyg_packages/standard/index.eyg.json")
    {:ok, tree} = :gleam@json.parse(json, :eyg@ir@dag_json.decoder(nil))
    tree
  end

  @doc "A fetch function serving each `{name, tree}` as version 1 of a package."
  def fetch(packages) do
    test = self()

    entries =
      packages
      |> Enum.with_index(1)
      |> Enum.map(fn {{name, tree}, cursor} -> entry(name, cursor, cid(tree)) end)

    modules =
      Map.new(packages, fn {_name, tree} ->
        {cid_string(cid(tree)), :eyg@ir@dag_json.to_block(tree)}
      end)

    fn request ->
      url = :gleam@uri.to_string(:gleam@http@request.to_uri(request))
      send(test, {:hub_request, url})
      fn k -> k.({:ok, response(url, request, entries, modules)}) end
    end
  end

  @doc "Configure the application to use a fetch function, for the rest of the test."
  def use_fetch(fetch) do
    Application.put_env(:ash_eyg, :hub, "https://hub.test")
    Application.put_env(:ash_eyg, :package_fetch, fetch)

    ExUnit.Callbacks.on_exit(fn ->
      Application.delete_env(:ash_eyg, :hub)
      Application.delete_env(:ash_eyg, :package_fetch)
    end)
  end

  @doc "A fetch function that fails the test if called."
  def no_fetch, do: fn request -> raise "unexpected request #{inspect(request)}" end

  defp response("https://hub.test/packages/pull" <> _, request, entries, _modules) do
    since =
      case :gleam@http@request.get_query(request) do
        {:ok, [{"since", number}]} -> String.to_integer(number)
        _ -> 0
      end

    page = entries |> Enum.filter(&(elem(&1, 1) > since)) |> Enum.take(1)

    {:response, 200, [],
     :gleam@json.to_string(:untethered@ledger@schema.entries_response_encode(page))}
  end

  defp response("https://hub.test/modules/" <> cid, _request, _entries, modules) do
    case Map.fetch(modules, cid) do
      {:ok, body} -> {:response, 200, [], body}
      :error -> {:response, 204, [], ""}
    end
  end

  defp entry(name, cursor, module) do
    identity = cid(parse("0"))
    entry = {:entry, 1, :none, identity, "test-key", {:release, name, 1, module}}
    payload = :gleam@json.to_string(:eyg@hub@publisher.encode(entry))
    {:archived_entry, cursor, identity, payload, identity, 1, :none, "release"}
  end

  def parse(source) do
    {:ok, tree} = :eyg@parser.all_from_string(source)
    tree
  end

  defp cid(tree) do
    task =
      :eyg@ir@cid.from_tree(tree, fn bytes -> fn k -> k.(:crypto.hash(:sha256, bytes)) end end)

    task.(fn value -> value end)
  end

  defp cid_string(cid), do: :multiformats@cid@v1.to_string(cid)
end
