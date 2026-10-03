defmodule PhoenixCounters.EygTest do
  use ExUnit.Case

  import PhoenixCounters.HubFixture
  alias PhoenixCounters.Counters
  alias PhoenixCounters.Counters.Eyg

  @empty :eyg@hub@cache.empty()

  defp requests do
    receive do
      {:hub_request, url} -> [url | requests()]
    after
      0 -> []
    end
  end

  test "check fetches the packages a script refers to and run reuses them" do
    use_fetch(fetch([{"standard", standard()}]))
    source = ~s|@standard.list.map(["checked"], (name) -> { perform StartCounter(name) })|

    {{:ok, _type}, cache} = Eyg.check(source, @empty)
    assert requests() != []
    assert Counters.get_value("checked") == {:error, :not_found}

    assert {{:ok, {:linked_list, [_]}}, ^cache} = Eyg.run(source, cache)
    assert requests() == []
    :ok = Counters.shutdown("checked")
  end

  test "only referenced packages are fetched" do
    use_fetch(fetch([{"prices", parse("11")}, {"standard", parse("99")}]))
    assert {{:ok, {:integer, 11}}, _cache} = Eyg.run("@prices", @empty)
    modules = for "https://hub.test/modules/" <> cid <- requests(), do: cid
    assert length(modules) == 1
  end

  test "scripts without references make no requests" do
    use_fetch(no_fetch())
    assert {{:ok, "Integer"}, @empty} = Eyg.check("!int_add(1, 2)", @empty)
    assert {{:error, _}, @empty} = Eyg.run("!int_add(1", @empty)
  end

  test "a type error anywhere stops every effect" do
    use_fetch(no_fetch())
    source = ~s|let _ = perform StartCounter("early")\nperform GetValue(3)|
    assert {{:error, message}, @empty} = Eyg.run(source, @empty)
    assert message =~ "type mismatch given: Integer expected: String"
    assert Counters.get_value("early") == {:error, :not_found}
  end

  test "a failed load returns the cache it was given" do
    use_fetch(fetch([{"standard", parse("42")}]))
    {{:ok, "Integer"}, cache} = Eyg.check("@standard", @empty)
    assert {{:error, message}, ^cache} = Eyg.check("@missing", cache)
    assert message =~ "missing"
    assert {{:ok, {:integer, 42}}, ^cache} = Eyg.run("@standard", cache)
  end

  test "the scripts process keeps its cache between calls" do
    use_fetch(fetch([{"standard", parse("42")}]))
    {:ok, scripts} = PhoenixCounters.Scripts.start_link([])
    assert PhoenixCounters.Scripts.check(scripts, "@standard") == {:ok, "Integer"}
    assert requests() != []
    assert PhoenixCounters.Scripts.run(scripts, "@standard") == {:ok, {:integer, 42}}
    assert requests() == []
  end
end
