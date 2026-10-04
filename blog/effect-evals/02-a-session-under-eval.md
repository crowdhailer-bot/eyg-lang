---
name: A session under eval
description: Running the real agent against fixtures by performing its effects yourself.
---

# A session under eval

An eval is only worth the trust you put in it if the thing it measures is the
thing people use. The easiest way to break that is to build a second, simpler
agent for the eval: a loop that calls the model, runs the code and stops. It
will diverge from the product within a week.

Overlay does not need one. Its session is a state machine: a message goes in, a
new state and a list of effects come out.

```gleam
pub fn update(
  state: State,
  message: Message,
) -> #(State, List(system.Effect(Message)))
```

In the browser those effects are performed by the platform. In an eval they are
performed by the runner, against fixtures:

```gleam
fn perform(session, effect) {
  case effect {
    system.Fetch(request:, resume:) -> // the environment answers, or refuses
    system.FetchStreamResponse(request:, resume:) -> // the model answers
    system.GetSessionStorageItem(key:, resume:) -> // the settings of the model under eval
    system.Alert(message:, resume:) -> // logged, then resumed
    ...
  }
}
```

Everything else is the product: the same system prompt, the same type checking
before a program runs, the same tool results sent back to the model. When the
prompt changes, the eval sees the change.

## The model is just another effect

Completions arrive through `FetchStreamResponse`, so the model is chosen by
answering that one effect. There are three useful answers.

**A provider.** Ollama Cloud, a local Ollama, Mistral. Switching provider or
model changes nothing else about a session, so a suite can be run across a
matrix of models.

**A cassette.** Record what a provider streamed, replay it later. A replayed
run grades identically without calling a model, which makes it possible to
change a grader and re-grade yesterday's run, or to run the harness in CI. A
replayed request that no longer matches its recording is an error, not a
warning: the session changed, and the recording is stale.

**A script.** A function from the conversation to the next reply. This is the
one that makes tasks trustworthy, and it is the subject of the next post.

## The transcript is the artefact

When a session finishes, what is kept is not the chat log. It is:

- each turn, with the agent's replies,
- every program it ran, with the value it computed or why it failed: a type
  error, an exception, an abort,
- every effect that reached the environment, marked as the program's own or as
  Overlay loading modules,
- the workspace it left behind,
- why the session stopped: finished, the model call limit, a model failure.

Graders read that. They never re-run a session, so grading is cheap,
repeatable, and can be done again later with a better grader.

One detail worth copying if you build something similar: Overlay used to keep
only the text it sent back to the model, because that is all the chat needed.
Values were formatted and thrown away. Evals need the values themselves, so the
session now keeps the outcome of every finished run. It was a four line change
that made a whole class of checks possible, and the page can use it too.
