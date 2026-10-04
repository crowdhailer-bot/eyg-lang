defmodule Helpdesk.Triage do
  @moduledoc """
  Run scripts that sort out who works on which ticket.

  A triage script can read tickets and representatives and assign tickets,
  it is a type error for one to open or close a ticket.
  """

  def effects do
    AshEyg.effects(otp_app: :helpdesk)
    |> Enum.filter(&(&1.action in [:read, :assign]))
  end

  def check(source), do: AshEyg.Session.check(Helpdesk.Scripts, source, effects: effects())

  def run(source, actor \\ nil),
    do: AshEyg.Session.run(Helpdesk.Scripts, source, effects: effects(), actor: actor)
end
