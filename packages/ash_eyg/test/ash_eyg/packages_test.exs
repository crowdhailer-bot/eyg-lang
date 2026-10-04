defmodule AshEyg.PackagesTest do
  use ExUnit.Case

  import AshEyg.Test.HubFixture

  @actor %{id: "admin"}

  defp effects, do: AshEyg.effects(domains: [AshEyg.Test.Support])

  defp requests do
    receive do
      {:hub_request, url} -> [url | requests()]
    after
      0 -> []
    end
  end

  test "check fetches what a script refers to and run reuses the cache" do
    use_fetch(fetch([{"standard", standard()}]))
    source = "@standard.list.map([1, 2], (x) -> { !int_add(x, 1) })"

    {{:ok, "List(Integer)"}, cache} =
      AshEyg.check(source, AshEyg.empty_cache(), effects: effects())

    assert requests() != []
    assert {{:ok, _}, ^cache} = AshEyg.run(source, cache, effects: effects(), actor: @actor)
    assert requests() == []
  end

  test "only referenced packages are fetched" do
    use_fetch(fetch([{"prices", parse("11")}, {"standard", parse("99")}]))

    assert {{:ok, {:integer, 11}}, _cache} =
             AshEyg.run("@prices", AshEyg.empty_cache(), effects: effects())

    assert length(for "https://hub.test/modules/" <> cid <- requests(), do: cid) == 1
  end

  test "scripts without references make no requests" do
    use_fetch(no_fetch())
    empty = AshEyg.empty_cache()
    assert {{:ok, "Integer"}, ^empty} = AshEyg.check("!int_add(1, 2)", empty, effects: effects())
  end

  test "a failed load returns the cache it was given" do
    use_fetch(fetch([{"standard", parse("42")}]))

    {{:ok, "Integer"}, cache} =
      AshEyg.check("@standard", AshEyg.empty_cache(), effects: effects())

    assert {{:error, _}, ^cache} = AshEyg.check("@missing", cache, effects: effects())
  end

  test "a session keeps its cache between calls" do
    use_fetch(fetch([{"standard", parse("42")}]))
    {:ok, session} = AshEyg.Session.start_link([])
    assert AshEyg.Session.check(session, "@standard", effects: effects()) == {:ok, "Integer"}
    assert requests() != []
    assert AshEyg.Session.run(session, "@standard", effects: effects()) == {:ok, {:integer, 42}}
    assert requests() == []
  end
end
