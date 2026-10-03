# AshEyg

Expose your [Ash](https://ash-hq.org) domains to [EYG](https://eyg.run) scripts.

Every action of an exposed resource is an EYG effect with a type.
Scripts are type checked against the effects you give them before they run,
so a script cannot call an action it was not given, or call one with the wrong input.
The actor, tenant and context of a run are given to every action, a script cannot read or change them.

## Installation

```elixir
def deps do
  [
    {:ash_eyg, path: "path/to/eyg-lang/packages/ash_eyg"}
  ]
end
```

`ash_eyg` depends on [`eyg_beam`](../eyg_beam), building it needs `gleam`.

Add `AshEyg.Domain` to a domain and `AshEyg.Resource` to the resources scripts can use.

```elixir
defmodule Helpdesk.Support do
  use Ash.Domain, extensions: [AshEyg.Domain]
end

defmodule Helpdesk.Support.Ticket do
  use Ash.Resource,
    domain: Helpdesk.Support,
    extensions: [AshEyg.Resource]
end
```

## Effects

An effect is labelled by its domain, resource and action, `Helpdesk.Support.Ticket` action `:open` is `SupportTicketOpen`.
Override the parts with `eyg do name "..." end` in the domain or resource, and hide a resource with `expose? false`.

| Action    | Lift                                   | Reply                             |
| --------- | -------------------------------------- | --------------------------------- |
| `read`    | arguments                              | `Result(List(record), String)`    |
| `create`  | accepted attributes and arguments      | `Result(record, String)`          |
| `update`  | primary key, attributes and arguments  | `Result(record, String)`          |
| `destroy` | primary key and arguments              | `Result({}, String)`              |
| `action`  | arguments                              | `Result(returns, String)`         |

A record has the primary key and public attributes of the resource.
An input that is not required is an option, `None({})` leaves it out.
Strings, uuids, decimals, floats, dates and times are strings, `one_of` atoms are unions, see `AshEyg.Type`.

List the effects of an application with their types.

```sh
mix ash_eyg.effects
```

## Running scripts

```elixir
effects = AshEyg.effects(otp_app: :helpdesk)

{:ok, value} =
  AshEyg.run(~s|perform SupportTicketOpen({subject: "Printer on fire"})|,
    effects: effects,
    actor: current_user
  )

AshEyg.inspect(value)
# Ok({id: "...", subject: "Printer on fire", status: Open({})})
```

`AshEyg.check/2` type checks without running, errors are rendered against the source.
From the command line use `mix ash_eyg.check` and `mix ash_eyg.run` with a path or `-e`.

### Only some effects

The effects are a list, give a script only the ones it needs.

```elixir
effects =
  AshEyg.effects(otp_app: :helpdesk)
  |> Enum.filter(&(&1.action in [:read, :assign]))
```

### Host effects

Add effects of your own with `AshEyg.Effect.new/4`.

```elixir
log =
  AshEyg.Effect.new("Log", :string, {:record, :empty}, fn {:string, message}, _opts ->
    Logger.info(message)
    {:record, %{}}
  end)

AshEyg.run(source, effects: [log | effects])
```

## Example

[`examples/helpdesk`](../../examples/helpdesk) is the Ash getting started project with EYG set up.
