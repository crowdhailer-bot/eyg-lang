defmodule Helpdesk.ScriptTest do
  use ExUnit.Case

  defp run(source) do
    Helpdesk.Scripting.Script
    |> Ash.ActionInput.for_action(:run, %{source: source})
    |> Ash.run_action()
  end

  test "scripts use the standard library and the helpdesk" do
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
