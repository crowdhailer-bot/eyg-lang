defmodule PhoenixCountersWeb.HomeLiveTest do
  use PhoenixCountersWeb.ConnCase

  import Phoenix.LiveViewTest

  alias PhoenixCounters.Counters

  test "shows type errors for programs that parse", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    refute view |> element("#script") |> render_change(%{source: "perform StartCounter("}) =~
             "error:"

    html = view |> element("#script") |> render_change(%{source: "perform StartCounter(1)"})
    assert html =~ "type mismatch given: Integer expected: String"
  end

  test "runs a script and lists the counters it started", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html =
      view
      |> element("#script")
      |> render_submit(%{
        source: ~s|@standard.list.map(["live_a", "live_b"], (n) -> { perform StartCounter(n) })|
      })

    assert html =~ "[Ok({}), Ok({})]"
    assert has_element?(view, "#counters td", "live_a")
    assert has_element?(view, "#counters td", "live_b")
    assert_push_event(view, "clear", %{})

    :ok = Counters.shutdown("live_a")
    :ok = Counters.shutdown("live_b")
  end

  test "does not run badly typed scripts", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html =
      view
      |> element("#script")
      |> render_submit(%{source: ~s|let _ = perform StartCounter("never")\nperform GetValue(1)|})

    assert html =~ "error:"
    assert Counters.get_value("never") == {:error, :not_found}
  end
end
