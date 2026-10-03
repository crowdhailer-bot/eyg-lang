---
title: Using EYG in Ash
date: 2026-10-03
---

# Using EYG in Ash

[`ash_eyg`](../../packages/ash_eyg) turns every action of your Ash resources into a typed EYG effect.
Scripts are type checked against the effects you give them, then run with your actor, tenant and context.

This post adds it to the project from the Ash [getting started guide](https://hexdocs.pm/ash/get-started.html).
The finished project is [`examples/helpdesk`](../../examples/helpdesk).
The video sets EYG up in a shell, then runs scripts from AshAdmin.

<video src="demo.mp4" controls width="100%"></video>

## 1. Add the dependency

```elixir
# mix.exs
defp deps do
  [
    {:ash, "~> 3.0"},
    {:ash_eyg, path: "../../packages/ash_eyg"}
  ]
end
```

```sh
mix deps.get
```

`ash_eyg` depends on `eyg_beam`, the EYG parser, type checker and interpreter compiled from Gleam.
Mix builds it with `make`, so `gleam` must be on your path.

## 2. Expose the domain and resources

Add `AshEyg.Domain` to the domain.

```elixir
# lib/helpdesk/support.ex
defmodule Helpdesk.Support do
  use Ash.Domain, extensions: [AshEyg.Domain]

  resources do
    resource Helpdesk.Support.Ticket
    resource Helpdesk.Support.Representative
  end
end
```

Add `AshEyg.Resource` to each resource scripts can use.

```elixir
# lib/helpdesk/support/ticket.ex
use Ash.Resource,
  domain: Helpdesk.Support,
  data_layer: Ash.DataLayer.Ets,
  extensions: [AshEyg.Resource]
```

## 3. List the effects

```sh
mix ash_eyg.effects
```

```
SupportTicketOpen
  lift:  {subject: String}
  reply: [Ok: {id: String, subject: String} | Error: String]

SupportTicketAssign
  lift:  {id: String, representative_id: [Some: String | None: {}]}
  reply: [Ok: {id: String, subject: String} | Error: String]
```

Labels are domain, resource and action.
The lift is a record of the action's inputs, an optional input is an option.
Updates and destroys also take the primary key.
The reply is a `Result`, errors are strings.

Records only have the primary key and public attributes.
The guide leaves `status` private, make it public to give scripts access.

```elixir
attribute :status, :atom do
  constraints one_of: [:open, :closed]
  default :open
  allow_nil? false
  public? true
end
```

`one_of` atoms become unions, `status` is `[Open: {} | Closed: {}]`.

## 4. Run a script

```sh
mix ash_eyg.run -e 'perform SupportTicketOpen({subject: "Printer on fire"})'
```

```
Ok(
  {
    id: "80c86eb9-f02a-4ef4-842d-381d5fb35c6f",
    status: Open({}),
    subject: "Printer on fire",
  }
)
```

The tasks give a script every effect and no actor.
`mix ash_eyg.check` type checks without running.

```sh
mix ash_eyg.check -e 'perform SupportTicketOpen({subject: 42})'
```

```
error: type mismatch given: Integer expected: String
hint: check the expression matches the expected type

 1 | perform SupportTicketOpen({subject: 42})
     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
```

## 5. Run scripts from your application

```elixir
effects = AshEyg.effects(otp_app: :helpdesk)

case AshEyg.run(source, effects: effects, actor: current_user) do
  {:ok, value} -> AshEyg.inspect(value)
  {:error, message} -> message
end
```

`actor`, `tenant` and `context` are passed to every action, so your policies apply.
Scripts cannot read or change them.

## 6. Give a script only some effects

`AshEyg.effects/1` returns a list, each effect has its `resource` and `action`.

```elixir
defmodule Helpdesk.Triage do
  def effects do
    AshEyg.effects(otp_app: :helpdesk)
    |> Enum.filter(&(&1.action in [:read, :assign]))
  end

  def run(source, actor), do: AshEyg.run(source, effects: effects(), actor: actor)
end
```

A triage script that opens a ticket does not type check, so it never runs.

```
error: missing row 'SupportTicketOpen'
```

This triage script assigns every ticket to the first representative.

```eyg
match perform SupportTicketRead({}) {
  Ok(tickets) -> {
    match perform SupportRepresentativeRead({}) {
      Ok(representatives) -> {
        match !list_pop(representatives) {
          Ok({head: representative, tail: _}) -> {
            !list_fold(tickets, [], (ticket, assigned) -> {
              let _ = perform SupportTicketAssign({id: ticket.id, representative_id: Some(representative.id)})
              [ticket.subject, ..assigned]
            })
          }
          Error(_) -> { [] }
        }
      }
      Error(_) -> { [] }
    }
  }
  Error(_) -> { [] }
}
```

## 7. Add effects of your own

```elixir
log =
  AshEyg.Effect.new("Log", :string, {:record, :empty}, fn {:string, message}, _opts ->
    Logger.info(message)
    {:record, %{}}
  end)

AshEyg.run(source, effects: [log | Helpdesk.Triage.effects()])
```

## 8. Run scripts from AshAdmin

Ash itself has no views, [AshAdmin](https://hexdocs.pm/ash_admin) is its admin UI.
AshAdmin renders a form for any generic action and shows its result, so a script page is one action.

```elixir
defmodule Helpdesk.Scripting.Script do
  use Ash.Resource, domain: Helpdesk.Scripting, extensions: [AshAdmin.Resource]

  admin do
    form do
      field :source, type: :long_text
    end
  end

  actions do
    action :run, :string do
      argument :source, :string, allow_nil?: false

      run {AshEyg.RunScript,
           otp_app: :helpdesk,
           packages: %{"standard" => Application.compile_env!(:helpdesk, :standard_library)}}
    end
  end
end
```

`AshEyg.RunScript` runs the script as the actor chosen in AshAdmin and returns its value as EYG.
A type error is an invalid `source` argument, so AshAdmin shows it under the box.
The `packages` option makes `@standard` available, loaded once from its IR JSON.

```eyg
let subjects = ["Printer on fire", "Mouse will not click", "Coffee machine is empty"]
@standard.list.map(subjects, (subject) -> {
  perform SupportTicketOpen({subject: subject})
})
```

Mount AshAdmin in the router as usual.

```elixir
scope "/" do
  pipe_through [:browser, HelpdeskWeb.EygHighlight]
  ash_admin "/admin"
end
```

AshAdmin renders its own layout with its own JavaScript, there is no place for an application's script.
`HelpdeskWeb.EygHighlight` is a plug that adds one to AshAdmin pages before they are sent.
The script highlights with [shiki](https://shiki.style) and the TextMate grammar from the EYG VS Code extension.
It draws the highlighted source over the `source` textarea, whose own text is transparent, and highlights each result as AshAdmin renders it.
See [`assets/js/admin_eyg.js`](../../examples/helpdesk/assets/js/admin_eyg.js).

## Options

- Rename the label parts with `eyg do name "Desk" end` in a domain or resource.
- Hide a resource with `eyg do expose? false end`.
- Fields of types `ash_eyg` cannot represent are left out, see `AshEyg.Type`.
