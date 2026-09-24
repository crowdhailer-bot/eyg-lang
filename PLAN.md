# Fast Code

EYG is an Intermediate Representation (IR or AST) first language.
It is expected that tools can build on it's structure without reimplementing paring logic.

## Structured editing

Structural (or projectional) editing is when changes to a program are performed by manipulation of the tree structure of a programs.
This is instead of editing text files.

The EYG repository contains a structural editor built on the canonical IR.
- `packages/gleam_ir` the canonical data types for a Gleam program
- `packages/gleam_analysis` implements type checking for the IR
- `packages/morph` implements a higher level representation `Editable` and a zipper for the structure `Projection`
- `packages/webside` implements the end structural editor. 
  The editor in routes/documentation/state is the most reliable `user_pressed_key` function maps keys to transformations of the AST.

## Jev

Jev is a new AI (not LLM) that chooses from a list of options a best action based on the given input and list of actions.
The full context on what Jev is is available at https://docs.typesafe.ai/llms.txt

Presenting Jev with a current program and all the sound structural edits that can be made is a great paring.


## Roadmap

Everything will be written in Gleam, use the Lustre framwork for the web page.
Search packages.gleam.run for useful packages whenever possible.
If any packages need changes are are not in this repo, vendor them in, use them as path dependencies and make the fixes required.
Add any extra tasks for each step in the lists below. Solve everything including the new task items

### Prerequisits

- [x] Create an API client for the Jev API
  - Documentation is available here https://docs.typesafe.ai/api.md
  - create a new package called jev and rely on it as a path dependency
  - [x] `packages/jev`, sans-io operations and decoders tested on Erlang and JavaScript
  - [x] Browsers are refused by CORS, the playground dev server proxies `/v1` and holds the key
- [x] Jev needs the current state of a program implement AST to text code.
  - [x] Ensure the syntax matches that used by the parser, up to the point of indicating a cursor
    - `morph/text`, every file in `eyg_packages` prints and parses back to the same tree
  - [x] There nees to be a way to identiy what is currently selected. Make sure Jev can clearly undersand the current focus (1 or many).
    - any number of paths can be marked, the selection is shown `«like this»`
  - [x] Fix `morph/buffer` looking up scope and arity with the path the wrong way round

### Basic edits

Call the API with:
1. The task
2. The current state of the program
3. Any type errors in the current program
4. A list of AST manipulations that are possible at that point.
  - Include move left/right increase selection
  - Include jump to any type error.

- [x] Create a new project jev-playground
- [x] Create a new route which starts the jev-playground with an empty program
- [x] Show a textbox where there user can ask a question.
- [x] A loop that will keep calling Jev implement the returned manipulation and continue in a loop
  - [x] Jev cannot generate text, offer names and literals from the task, the program and common names
  - [x] Move to the next `?` after a hole is filled with a complete value, Jev kept replacing the same hole
  - [x] Name options by their result, for example `call !int_add(?, ?)`
  - [x] Keep to the 255 option limit by dropping builtins first and not offering names already in scope
- [x] record a video with mocked jev responses of it working through the process of creating a API client for github.
  - [x] Synthesise the actions that build a target program so the mocked script matches the editor
  - [x] A test replays each demo and fails if any scripted choice was not offered
  - Give it explicit instructions of three enpoints to implement.
  - Make sure it understands the effect environment. it should be able to write and run tests.
  - Make it look technical, show jev thinking time for each option, show what options was presented and what was selected.
    The selected option should slide into a list that shows the last 8 selections before the oldest fades out

### Compound moves

Look at each file in the eyg_packages directory.
- [x] Find a string of transformations that moves from the empty program to the library function as it exits today.
  - 434 of 436 definitions, `gleam run -m jev_playground/mine`, each typed in the scope of its file
  - [x] Fix `morph` navigation looping forever looking for a `?` when there is none
  - [x] Fix `morph` paths to the original record of an overwrite of several fields
- [x] Find the most common compound moves. i.e. a series of transformations that repeat in different contexts.
  - Make sure that you consider ones have the same structural modification but use different variable names.
  - [x] Find 10 compound strings to start with, see `packages/jev_playground/research/compound_moves.md`
- [x] record a video of jev creaing the http library, with mocked responses, First without the compound options second with the compound options.
  - [x] Ask for names, labels and many literals in separate questions, a long task offered more than 255 options
  - [x] Find demo scripts when building the playground, finding them in the browser was slow

### Adding libraries

- [x] Add the option to search the library as a choice for jev to make
  - `Config(search_libraries:)` offers to open each library that is not yet open
  - [x] Bundle the `eyg_packages` libraries with their releases, relative imports become content references
  - [x] Annotate library trees directly, the continuation passing rewrite in `eyg_ir` overflowed the browser stack
- [x] When a library is selected add the functions an types to the state sent to the endpoint.
  - [x] Show types without effect rows and with letters for type variables, the raw types were long and hard to read
- [x] Record a video of Jev writing the Github library using the compound actions and the @http library
  - `/demo/github-library`, 105 choices of which 21 are compound

### Real API

- [x] Use the provided API token
  - The key stays out of git and the browser, the dev server and eval runner read `TYPESAFE_API_KEY`
  - [x] Check the API client is accurate
    - [x] record error responses and update an required tests
      - `packages/jev/test/fixtures` are real responses, including a request refused for too many tokens
    - [x] write API documentation, `packages/jev/README.md`
    - [x] Report a request of more than about 32,800 input tokens as `TooManyTokens`
- [x] Write an eval that takes a prompt, starting program and loops until the output is correct.
  - `gleam run -m jev_playground/evaluate`, a checker calls the program and its verdict is shown to Jev as test results
  - [x] run an eval that creates a program to calculate the first n fibonacci numbers.
    - never solved from an empty program, solved from a scaffold in 21 steps for $0.0043
  - [x] run an eval that adds new list functions to the existing standard library.
    - never solved from the library alone, solved from a scaffold in every run once the selected code is repeated for Jev
  - [x] Add evals for a greeting, a record, an order total and a match, and a sweep that runs each with a set of variants
  - [x] Resolve the types in scope with what inference learnt later, every parameter was type `a`
  - [x] Describe a hole in a match branch by its tag, and keep the arity a call was offered with
  - [x] Stop loops that move back to repeat an edit, calls grew until a request was refused
  - [x] Stop evaluating a program after a million steps, one grew until the kernel killed the eval
  - [x] Fail rather than crash when focusing on a path that is not in the program
- [x] The output of an eval should include a realtime video of the progress of the program. Show the program as it was to the amount of time jev was thinking about it.
  - `/eval/<file>` replays a saved run, `record` turns it into a video
- [x] Investigate the effect of the compound actions on the cost and speed of jev reaching a solution.
  - `packages/jev_playground/research/evals.md`, compounds helped one scaffold, broke two and added 14% to each request
  - [x] Write evals that allow you to discover better compound actions. Weigh up the cost of more options against the ability to make larger transformations for each decision
    - the number of compounds and instances of each are variant flags, `checked` offers only instances that type check
- [x] Do deep research into the best way to use type information to guide choices.
  - `packages/jev_playground/research/type_information.md`, the types in scope had not been resolved, fixed in `eyg_analysis`
  - [x] Repeat the selected code in the description of the selection by default, the best variant measured
  - Type information of all vacant nodes can be shown, `types`
  - Type information of all nodes with an effect can be shown, designed but not measured as no eval performs effects
  - What is the best way to highlight the current selection, `mark=`
- [x] Do deep research into giving jev the ability to have multiple cursors at a time.
  - `packages/jev_playground/research/cursors_and_jumps.md`, `cursors=3` asks what fills the next holes in the same request, which solved fewer evals
- [x] Do deep research into the ability to jump around the program. I think that jump to type errors is the most valuable power. but maybe there are times it doesn't work.
  - `packages/jev_playground/research/cursors_and_jumps.md`, `gleam run -m jev_playground/runs` reports how saved runs moved
  - jumping to type errors made no measurable difference, moving to any hole by number made results worse
- [x] Suggest and test any other improvements that will allow jev to work towards the correct solution quicker.
  - `packages/jev_playground/research/improvements.md`
  - [x] Stop a run after three choices in a row below 0.2 confidence, 1 of 357 solved runs did so

### Contexts and effects

- [x] Add effect nodes, what each call in the program performs, and measure the ways of showing effects
  - `effect_at` in `eyg_analysis`, `effects=hidden|signatures|calls|nodes|callsonly` are variant flags
- [x] Use Jev from the overlay page
  - Jev is a provider, requests go to `/v1` on the page's origin, which forwards them to TypeSafe with the person's key
  - Jev is shown what each new program returns and the answer is the program it finishes with
- [x] Create the best DNSimple context, `eyg_packages/dnsimple`
  - [x] Pass on the message DNSimple gives when a call fails
  - [x] Take a host wherever a domain is taken, Jev wrote `api.lovelace.dev` as the domain in every run
- [x] Evals that reference the context by content id, shared to the local hub, with no scaffold
  - [x] The context readme is in the state and compounds are built from the functions of the context
  - [x] Twenty questions a person might ask of their DNSimple account, each started from an empty program
  - [x] Offer to select each argument of a complete program, and fix the selection after a wrap and after a function argument
- [x] Review the ways of building compounds from a context and of showing effects, `packages/jev_playground/research/contexts.md`

### A context of endpoints

- [x] Reduce the DNSimple context to one function per API endpoint, named as DNSimple names the operation
  - [x] No list helpers of its own, a program opens `@standard` for those
  - [x] Pass on what the API says when a call fails
- [x] Let Jev pull a library
  - [x] Its functions are offered as calls, wraps and values once it is open, as the context's are
  - [x] A library the program already references counts as open
  - [x] A release is written `@standard:1:baguq…` in the tree and read as `@standard`
  - [x] Pass the selection as the first argument of a call taking several, in `morph`
- [x] Thirty one questions a person would ask of their account, eighteen answered from an empty program
- [x] Show what Jev writes properly on the overlay page
  - [x] One syntax highlighter, shared by the playground and the overlay
  - [x] Long lines wrap in the chat rather than scrolling sideways
  - [x] Every edit listed under the answer with its confidence and time, opened and scrolled by the reader
- [x] Record the videos, `jev_playground/frames` replays saved runs into the frames of one

## Rollout

This branch is 142 commits. Nothing here is meant to land as one change: the list below is the order to
review it in, from the fixes that stand alone to the features that need everything under them.
Each step says how it is tested and what would make it acceptable, so a step can be taken on its own,
and a step can be rejected without blocking the ones below it.

The whole branch is green: `gleam format --check`, `gleam build --warnings-as-errors` and `gleam test` pass
in every package it touches, and `CONTRIBUTING.md` lists
the commands. Anything measured against Jev costs money, so a reviewer repeating a measurement should
expect to pay: a sweep of the DNSimple questions is a few cents.

### 1. Fixes to the structural editor

Each is a bug found by driving `morph` harder than the editor does, and each stands alone.

| Change | Testing | Acceptable when |
| --- | --- | --- |
| `1dbecda` scope and arity looked up with the path reversed at the focus | `buffer_test`, shipped with the fix | The scope at a node matches what inference says, `morph` passes on both targets |
| `82e84be` searching for the next vacant looped forever when there was none | `navigation_test`, shipped with the fix | Navigation terminates on a program with no holes, and on every definition in `eyg_packages` when mined |
| `b190d47` the path to the original record of an overwrite of several fields | `editable/path_test`, shipped with the fix | Synthesis reaches the same tree for 434 of the 436 definitions in `eyg_packages` |
| `6f64af4` focusing a path that is not in the program crashed rather than failing | `buffer_test`, shipped with the fix | The call returns an error and no exception escapes |
| `cbba0e5` separators were not counted towards the line width when printing | `text_test`, shipped with the fix | Every file in `eyg_packages` prints and parses back to the same tree |
| `821f1df` a block ending in a function has no text syntax, now stated | **No test.** A reviewer decides whether the printer refuses it or the syntax is added | The limitation is asserted somewhere rather than only described |

### 2. New capability in the core libraries

Small additions the harness needs, each useful on its own and reviewable without the agent.

| Change | Testing | Acceptable when |
| --- | --- | --- |
| `f1df82f` a text printer for editable code with marked nodes | `text_test`, and every file in `eyg_packages` printed and parsed back | Any program prints with any set of marks and parses back to the same tree without them |
| `a813d1d` resolve the types in scope at a node with what inference learnt later | Tests shipped with it in `gleam_analysis`, 46 in the suite | A parameter reads as its inferred type rather than `a`, and the suite passes on both targets |
| `bdc2282` `effect_at`, the effects a node may perform, beside `type_at` | A test shipped with it over a program performing effects at known paths | The effects at a node match the row inference gives |
| `1a41bb9` walk a module without the stack | The `gleam_ir` suite, 29 tests, and loading `@standard` in a browser | A module the size of `@standard` is walked without overflowing the stack |
| `812269b` pass the selection as the first argument of a call taking several | **No test in `morph`.** Exercised only through the harness, by `wrap in @standard.list.map(.., f)`. Add transformation tests for arities 1 to 8 before it lands | The selection ends as the first argument with the rest as holes, at every arity, asserted in `morph` |

### 3. The Jev API client, `packages/jev`

A sans-io client for TypeSafe's System One: requests, questions, evaluations, and the errors the API gives.
It is a standalone piece of work and can be reviewed, and released, without anything else on this branch.

- **Testing.** 19 tests on both targets against recorded responses in `test/fixtures`, including the refusals:
  unauthorized, unknown model, no questions, no state, a choice of 256 options, a request over the token limit.
  No network in the tests; `client` in the playground is what sends them.
- **Acceptable when.** The fixtures are real responses from the API, a refusal decodes to a named error rather
  than a crash, and the package builds with `--warnings-as-errors` on Erlang and JavaScript.
- **Note for review.** `2f41b5d` reports a request over about 32,800 input tokens as `TooManyTokens`,
  which is the limit the API enforces and the harness has to respect.

### 4. The DNSimple context, `eyg_packages/dnsimple`

An EYG module with one function per DNSimple endpoint, its own JSON decoders, and a readme that documents
the API and the idioms for using it. Useful to anyone writing EYG against DNSimple, agent or not.

- **Testing.** `jev_playground/dnsimple_test` runs each function against an account served from memory
  and checks both what it returns and what it changed. A test checks the module in the repository has the
  content id the evals fetch.
- **Acceptable when.** Every function matches the endpoint it is named for, a failed call aborts with the
  message DNSimple gives, and the module type checks as one block with no references, which the hub enforces
  when it is shared.
- **Open question for review.** This context answers eighteen of thirty one questions from an empty program.
  The convenience context it replaced, with `records`, `without_auto_renew` and the rest, answered twenty of
  twenty. `research/contexts.md` has both sets of numbers; where a context should sit between the API and the
  question is the decision to review, and it is a product decision rather than a technical one.

### 5. The agent harness, `packages/jev_playground`

The largest part of the branch and the one to review last, because it rests on everything above.
It is research code: an agent, evals, sweeps and a page for watching a run.

- **Testing.** 74 tests covering the actions, the options offered at a focus, the state sent to Jev, the
  vocabulary, compound moves, and every eval's solution against its checker. Demos replay with each scripted
  choice asserted to have been offered, which is what catches an option disappearing.
- **Acceptable when.** The suite passes, every eval's reference solution passes its own checker, and a sweep
  reproduces the numbers in `research/`. The research documents are the argument for each default, and each
  default is a flag that can be turned off and measured.
- **Review in this order.** `action` and `options` (what Jev may choose), `agent` (what Jev is told),
  `eval` and the sweeps (how a claim is measured), then the page.

### 6. Effects, contexts and libraries in the harness

The features that make an empty program tractable. Each was measured and each can be turned off.

| Feature | Testing | Acceptable when |
| --- | --- | --- |
| Hole mode, the excerpt highlight, the type filter and the repeat filters | Sweeps with each turned off, three runs each | Every one is worth a solve or a large saving in tokens, as recorded in `research/improvements.md` |
| Compound moves from the context's functions | `dnsimple_test` asserts the options offered for each strategy; sweeps compare the strategies | Offering calls beats no compounds by 16 of 60 to 59 of 60, see `research/contexts.md` |
| Compound moves from the readme's examples | The same tests; a sweep with examples on and off | The default is the cheapest strategy that solves the most, and the caveat that examples shape the result is written down |
| Effects shown on the calls that perform them | Sweeps over five presentations | No presentation solves more, so the cheapest that still says which calls change the account wins |
| Pulling `@standard`: opening a library, its functions as compounds, references written short | Tests that a library is offered, that its calls appear once open, and that a referenced library counts as open | A question needing `map` or `filter` is answered from an empty program, which none were before |

### 7. The overlay page

Jev as a provider on a real page, answering questions about a real account.

- **Testing.** 54 tests in `overlay_web` over the state machine: asking, running, finishing, giving up,
  the Spotless token, and the libraries fetched at the start. The page itself is exercised by recording it.
- **Acceptable when.** A question typed into the page is answered by a program the person can read, the key
  never reaches the page's own code, and a question that cannot be answered gives up rather than looping.
- **Review together.** `jev_session` (the protocol), `state` (the loop), `libraries` (what a program may
  reference), and the view. `cb1f903` on `eyg.run` is the proxy that makes the key work in a browser.

### 8. What is not ready

- Thirteen of the thirty one questions are unanswered, and the two videos of failures show why:
  a run that gives up, and a run that finishes with a plausible answer to a different question.
- The blind protocol has no way to tell Jev it is wrong, which is honest but means a wrong answer is final.
- The demo rigs are in `tmp` and not committed, so the videos in `research/videos` are reproducible only
  with the pages beside them and a local hub.
