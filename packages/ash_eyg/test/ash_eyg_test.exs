defmodule AshEygTest do
  use ExUnit.Case, async: true

  alias AshEyg.Test.Ticket

  @actor %{id: "admin"}

  defp effects, do: AshEyg.effects(domains: [AshEyg.Test.Support])

  defp run(source, opts \\ []) do
    opts = Keyword.merge([effects: effects(), actor: @actor], opts)

    case AshEyg.run(source, opts) do
      {:ok, value} -> {:ok, AshEyg.inspect(value)}
      {:error, message} -> {:error, message}
    end
  end

  test "every action of an exposed resource is an effect" do
    labels = Enum.map(effects(), & &1.label)

    assert Enum.sort(labels) ==
             Enum.sort([
               "SupportTicketRead",
               "SupportTicketDestroy",
               "SupportTicketOpen",
               "SupportTicketClose",
               "SupportTicketByStatus",
               "SupportTicketCount"
             ])
  end

  test "domains and resources can be renamed" do
    assert [%{label: "DeskItemRead"}] = AshEyg.effects(domains: [AshEyg.Test.Named])
  end

  test "inputs are typed from attributes and arguments" do
    assert {:ok, type} =
             AshEyg.check(~s|perform SupportTicketOpen({subject: "Hi", priority: Some(1)})|,
               effects: effects()
             )

    assert type =~ "priority: [Some: Integer | None: {}]"
    assert type =~ "status: [Open: {} | Closed: {}]"

    assert {:error, message} =
             AshEyg.check(~s|perform SupportTicketOpen({subject: 1, priority: None({})})|,
               effects: effects()
             )

    assert message =~ "type mismatch given: Integer expected: String"
  end

  test "private attributes are not part of a record" do
    script = """
    match perform SupportTicketRead({}) {
      Ok(tickets) -> { !list_fold(tickets, "", (ticket, _) -> { ticket.secret }) }
      Error(reason) -> { reason }
    }
    """

    assert {:error, message} = AshEyg.check(script, effects: effects())
    assert message =~ "missing row 'secret'"
  end

  test "create, update, read and destroy records" do
    assert {:ok, {:tagged, "Ok", {:record, %{"id" => {:string, id}}}}} =
             AshEyg.run(
               ~s|perform SupportTicketOpen({subject: "Printer on fire", priority: None({})})|,
               effects: effects(),
               actor: @actor
             )

    assert {:ok, closed} = run(~s|perform SupportTicketClose({id: "#{id}"})|)
    assert closed =~ "status: Closed({})"
    assert run(~s|perform SupportTicketByStatus({status: Open({})})|) == {:ok, "Ok([])"}
    assert run(~s|perform SupportTicketDestroy({id: "#{id}"})|) == {:ok, "Ok({})"}
    assert run("perform SupportTicketRead({})") == {:ok, "Ok([])"}
  end

  test "generic actions return their value" do
    Ash.create!(Ticket, %{subject: "a"}, action: :open, actor: @actor)
    assert run("perform SupportTicketCount({})") == {:ok, "Ok(1)"}
  end

  test "the actor is given to every action" do
    assert {:ok, ~s|Error("forbidden")|} = run("perform SupportTicketRead({})", actor: nil)
  end

  test "a program can be given only some effects" do
    effects = Enum.filter(effects(), &(&1.action == :read))

    assert {:error, message} =
             AshEyg.check(~s|perform SupportTicketOpen({subject: "Hi", priority: None({})})|,
               effects: effects
             )

    assert message =~ "missing row 'SupportTicketOpen'"
  end

  test "host effects run alongside actions" do
    log =
      AshEyg.Effect.new("Log", :string, {:record, :empty}, fn {:string, message}, opts ->
        send(self(), {:log, message, opts[:actor]})
        {:record, %{}}
      end)

    assert {:ok, _} = run(~s|perform Log("hello")|, effects: [log | effects()])
    assert_received {:log, "hello", @actor}
  end
end
