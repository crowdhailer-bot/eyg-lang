defmodule Helpdesk.ScriptTest do
  use ExUnit.Case

  import Helpdesk.HubFixture

  defp run(source) do
    Helpdesk.Scripting.Script
    |> Ash.ActionInput.for_action(:run, %{source: source})
    |> Ash.run_action()
  end

  test "scripts use packages from the hub and the helpdesk" do
    use_fetch(fetch([{"standard", standard()}]))

    source = """
    @standard.list.map(["Printer on fire"], (subject) -> {
      perform SupportTicketOpen({subject: subject})
    })
    """

    assert {:ok, value} = run(source)
    assert value =~ ~s|subject: "Printer on fire"|
  end

  test "type errors are an invalid source" do
    assert {:error, %Ash.Error.Invalid{}} = run(~s|perform SupportTicketClose({subject: "x"})|)
  end
end
