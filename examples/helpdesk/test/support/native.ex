defmodule Helpdesk.TestNative do
  @moduledoc false
  def triage_check(source), do: Helpdesk.Triage.check(source)
  def triage_run(source), do: Helpdesk.Triage.run(source)

  def seed do
    ticket = Ash.create!(Helpdesk.Support.Ticket, %{subject: "Printer on fire"}, action: :open)

    representative =
      Ash.create!(Helpdesk.Support.Representative, %{name: "Joe Armstrong"}, action: :create)

    {ticket.id, representative.id}
  end

  def assigned(id), do: Ash.get!(Helpdesk.Support.Ticket, id).representative_id

  def script(source),
    do:
      Helpdesk.Scripting.Script
      |> Ash.ActionInput.for_action(:run, %{source: source})
      |> Ash.run_action()

  def invalid_argument(%Ash.Error.Invalid{errors: [error]}),
    do: {to_string(error.field), error.message}

  def fixture(fetch), do: Application.put_env(:ash_eyg, :package_fetch, fetch)
  def clear_fixture, do: Application.delete_env(:ash_eyg, :package_fetch)
end
