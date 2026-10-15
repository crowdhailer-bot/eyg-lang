---
name: Querying a todo list with EYG
description: Script a TodoMVC model through a deliberately limited typed interface.
---

# Querying a todo list with EYG

[examples/todomvc_lustre](../examples/todomvc_lustre/) gives the same todo model
to the host and an EYG shell. Programs can create, rename and complete tasks.
Deleting remains a host operation and is rejected by the script's type checker.

| Effect | Request | Reply |
| --- | --- | --- |
| ListTasks | {} | List({id, title, completed}) |
| CreateTask | String | Integer id |
| RenameTask | {id, title} | Ok({}) or Error(NotFound({})) |
| SetCompleted | {id, completed} | Ok({}) or Error(NotFound({})) |
| Print | String | {} |

The [EYG library](../examples/todomvc_lustre/library.eyg) is in scope as `todos`.
It adds case-insensitive matching, tags, active/completed queries and task helpers:

```eyg
let {list} = @standard:1:baguqeerahlbgfg7wjjdjguypivmsdcvh3e2vs4lhiafdbbtl3duxfuzv2eja
list.map(todos.tagged("#shopping"), todos.complete)
```

This completes all matching tasks through SetCompleted. A missing task returns
NotFound to the program. `perform DeleteTask(1)` fails before execution.

`todomvc/run.start(library, cache)` prepares the retained shell; `run.run` takes
that shell, the current task model and source. Its result contains updated
bindings, tasks, printed lines and the execution outcome. The host keeps these
returned values so a person and an agent can work with the same state.

The library pins standard version 1 and its CID. The host owns the hub cache
and passes cached module values and types to the shell. Reusing it retains
standard's evaluated value and type; retaining the shell also retains the
checked todos helpers. Recreating both starts fresh.

From examples/todomvc_lustre, run `gleam test` and `gleam test --runtime node`.
The tests use the repository's committed standard IR and verify its CID before
caching it. They check querying, changes, unavailable operations, missing tasks
and retained shell behavior without a network service.
