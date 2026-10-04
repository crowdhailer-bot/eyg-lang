defmodule AshEyg.RunScriptTest do
  # Uses the :ash_domains of the :ash_eyg application, set in config/config.exs
  use ExUnit.Case

  import AshEyg.Test.HubFixture
  alias AshEyg.Test.Scripts.Script

  defp run(source, actor \\ %{id: "admin"}) do
    Script
    |> Ash.ActionInput.for_action(:run, %{source: source}, actor: actor)
    |> Ash.run_action()
  end

  test "returns the value of the script" do
    source = ~s|perform SupportTicketOpen({subject: "Hi", priority: None({})})|
    assert {:ok, value} = run(source)
    assert value =~ ~s|subject: "Hi"|
  end

  test "scripts can use packages from the hub" do
    use_fetch(fetch([{"standard", standard()}]))
    assert run("@standard.list.map([1, 2], (x) -> { !int_add(x, 1) })") == {:ok, "[2, 3]"}
  end

  test "type errors are an invalid source" do
    assert {:error, %Ash.Error.Invalid{errors: [error]}} = run("perform Missing({})")
    assert error.field == :source
    assert error.message =~ "missing row 'Missing'"
  end

  test "scripts run as the actor of the action" do
    assert run("perform SupportTicketRead({})", nil) == {:ok, ~s|Error("forbidden")|}
  end
end
