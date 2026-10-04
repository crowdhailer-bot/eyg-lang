defmodule Helpdesk.TriageTest do
  use ExUnit.Case

  alias Helpdesk.Support.{Representative, Ticket}

  test "triage scripts cannot open tickets" do
    assert {:error, message} = Helpdesk.Triage.check(File.read!("scripts/open.eyg"))
    assert message =~ "missing row 'SupportTicketOpen'"
  end

  test "triage scripts assign tickets" do
    ticket = Ash.create!(Ticket, %{subject: "Printer on fire"}, action: :open)
    representative = Ash.create!(Representative, %{name: "Joe Armstrong"}, action: :create)

    assert {:ok, value} = Helpdesk.Triage.run(File.read!("scripts/triage.eyg"))
    assert AshEyg.inspect(value) =~ ~s|"Printer on fire"|
    assert Ash.get!(Ticket, ticket.id).representative_id == representative.id
  end
end
