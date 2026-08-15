# Tasks

All tasks are in support of creating a demonstration of how well EYG works as an embedded language.
The first example is create a page that shows that the language shell and overlay assistant can be integrated into a game.

## The game

A web app to play a hashiwokakero puzzle. 
The reference implementation is https://github.com/giacomocavalieri/hashi a browser version of the game that is implemented in Lustre and Gleam.

## The deliverably

A new package `hashi` that implements the frontend app to play the game via shell or Agent.
The web app shows the hashi game on the right and an EYG shell (or overlay agent) on the left.
The panel on the left shows a shell icon in which users then use the structural editor to write code
There is an agent icon in the left shell that allows switching to agent mode this allows writing english which will then be handled by an llm that returns tool calls to run EYG code
Clicking on the game has no effect all interaction is via Effects from the execution of EYG code.
The EYG harness has no other browser effects only the game effects are present.

Once the game is built I want a video of completing a whole game using the shell and a second video of completing the whole game using the agent.
There should be:
- A tutorial explaining to a technical audience how to build an embedded runtime with EYG
- A promotion page showing off how powerfull this is, why EYG is better than MCP as a way to expose something stateful to an agent.

### The Effect interface

- `ListIslands` returns a list of islands with fields for position, and expected number of connections
- `ListBridges` returns a list of bridges with start/end
- `AddBridge` takes start/end positions, returns Ok/Error the error is an enum of badstart/badend/Full/
- `ShareOutcome` When a game has finished you can post your result to bluesky. Do not use a builtin spotless effect. Use a Fetch effect and call spotless.run's device auth endpoint to post.
- `Undo`
- `Redo`

## Goals

- Rely on the existing giacomocavalieri/hashi project as much as possible.
  Clone it locally and depend on it as a path reference.
  Make as few changes as possible to the original project but make sure all rendering logic and game logic is depended on from the original project
  Document any changes needed in notes.md
- Use the context improvement in the overlay agent. This is on an in progress branch so you will need to base this work off that branch
- Make use of the components to build a structural editor in a shell
- Improve the API to overlay and other packages to make their reuse better
- Demonstrate the value of embedding EYG for both power users who like the shell and people wanting to add agents to their application.
- Complete test suite. Every change should be preceeded by a test

## Architecture

- `src/hashi/harness.gleam` defines all the effects needed to interact with the game.
  Modelled on the browser harness in touch_grass
- `src/hashi/platform.gleam` implements all the effects in the harness. it is built on pal/system.gleam abstraction
- `src/hashi/state.gleam` The state of the app. Follow the design of overlay_web/state
- `eyg/context.eyg` A context file that will be passed into the agent as a context and the shell as a predefined variable.
  It will include functions to find all islands with 2 as their target. Any helper on bridges and islands should be here. Make sure it is well documented

Other standard files as necessary

The application should run in vite the same as overlay_public

## Tasks

Write any tasks discovered during development into the list below

- [x] setup vite project
- [x] clone hashi project to neighbor directory
- [x] Write the harness
- [x] Render the game board on the page and connect the harness implementation to game state
- [x] Write a side bar with structural shell that has the harness effects when run
- [x] Write the toggle and agent implementation build on overlay_web compontents.
- [x] Take screenshots and ensure the styling is top quality and matches the original hashi style
- [x] mock responses from the agent to test running a whole game as an agent.
- [x] record shell video
- [x] record agent video
- [x] write tutorial — `guides/embedding_a_runtime.md`, published at /guides/building-an-embedded-runtime
- [x] write promotion page — `packages/website/src/website/routes/embedded.gleam`, at /embedded

### Discovered while building it

- [x] Give overlay an `Environment` so it can be embedded in something that is
      not a browser: the host state, a handler, the effects and the briefing.
- [x] Put the scope in the environment, so a host can hand over a library
      instead of making the model rebuild one out of raw effects.
- [x] Move the provider picker, the chat input and the drawn conversation out of
      `overlay_public` and into `overlay_web`, where another application can
      reach them. Same for `ui.code` into `morph/lustre/projection`.
- [x] `system.Sleep`, without which polling something that answers "not yet" is
      a hot loop.
- [x] A `browser` skill in the parent repo saying how this repo drives a
      browser, and why that is the one exception to the EYG-only rule.

Bugs found on the way, all fixed:

- [x] An effect that finished immediately returned its value as the answer of
      the whole program, throwing away everything after it. `perform Print(..)`
      followed by anything lost the anything.
- [x] The effect list in overlay's system prompt was written with an unclosed
      bracket.
- [x] The workspace readme was teaching `Error(BadStart(_))`, which EYG does not
      have — match takes apart one tag at a time.

### Still open

- [ ] spotless.run has no `bluesky` party, so `ShareOutcome` answers 404 today.
      The whole device-code flow is written and tested against the shape
      spotless already has. atproto wants DPoP-bound tokens, so adding the party
      is a piece of work in the spotless server rather than here. See
      `packages/hashi/notes.md`.
- [ ] `morph`'s picker decides with the value it was last rendered with, so
      typing a name and pressing enter in the same frame loses the last
      character.
- [ ] The change the demonstration needs in giacomocavalieri/hashi lives on a
      local branch of the clone and is not sent upstream: that project asks that
      LLM tools are not used to write issues or pull requests to it.