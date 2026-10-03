# Helpdesk

The project from the Ash [getting started guide](https://hexdocs.pm/ash/get-started.html), with its domain exposed to EYG scripts by [`ash_eyg`](../../packages/ash_eyg).

## Setting up EYG

1. Add the dependency, building it needs `gleam`.

   ```elixir
   # mix.exs
   {:ash_eyg, path: "../../packages/ash_eyg"}
   ```

2. Add `AshEyg.Domain` to the domain.

   ```elixir
   # lib/helpdesk/support.ex
   use Ash.Domain, extensions: [AshEyg.Domain]
   ```

3. Add `AshEyg.Resource` to each resource scripts can use.

   ```elixir
   # lib/helpdesk/support/ticket.ex
   use Ash.Resource,
     domain: Helpdesk.Support,
     data_layer: Ash.DataLayer.Ets,
     extensions: [AshEyg.Resource]
   ```

Every action is now an effect, list them with their types.

```sh
mix ash_eyg.effects
```

```
SupportTicketOpen
  lift:  {subject: String}
  reply: [Ok: {id: String, subject: String, status: [Open: {} | Closed: {}]} | Error: String]
```

Scripts only see public attributes, `status` is made public in this project.

## Running scripts

Scripts can use packages from the [hub](https://eyg.run), i.e. `@standard`, they are fetched when a script refers to them.

```sh
mix ash_eyg.check scripts/assign.eyg
mix ash_eyg.run scripts/assign.eyg
mix ash_eyg.run -e 'perform SupportTicketRead({})'
```

The tasks give a script every effect of the application.
From code, pass the effects a script may use.

```elixir
AshEyg.run(source, effects: AshEyg.effects(otp_app: :helpdesk), actor: current_user)
```

## Only some effects

[`Helpdesk.Triage`](lib/helpdesk/triage.ex) runs scripts that read tickets and representatives and assign tickets.

```elixir
def effects do
  AshEyg.effects(otp_app: :helpdesk)
  |> Enum.filter(&(&1.action in [:read, :assign]))
end
```

A triage script that opens a ticket is a type error, it never runs.

```elixir
iex> Helpdesk.Triage.check(File.read!("scripts/open.eyg"))
{:error, "error: missing row 'SupportTicketOpen'\n..."}
```

## AshAdmin

Scripts can also be run from [AshAdmin](https://hexdocs.pm/ash_admin).
[`Helpdesk.Scripting.Script`](lib/helpdesk/scripting/script.ex) has a `run` action that uses `AshEyg.RunScript`.
Scripts can use packages from the hub, i.e. `@standard`, the `Helpdesk.Scripts` session keeps them once fetched.

```sh
(cd assets && bun install)
mix assets.build
mix phx.server
```

Visit [`localhost:4000/admin`](http://localhost:4000/admin), open Scripting, Script.
Set `PORT` to use another port.

AshAdmin has no place for an application's scripts, so [`HelpdeskWeb.EygHighlight`](lib/helpdesk_web/eyg_highlight.ex) adds [`admin_eyg.js`](assets/js/admin_eyg.js) to its pages.
It highlights the script and its result with the TextMate grammar from [`packages/vscode-eyg`](../../packages/vscode-eyg).

## Test

```sh
mix test
```
