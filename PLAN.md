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

- [ ] Add the option to search the library as a choice for jev to make
- [ ] When a library is selected add the functions an types to the state sent to the endpoint.
- [ ] Record a video of Jev writing the Github library using the compound actions and the @http library

### Real API

- [ ] Use the provided API token
  - [ ] Check the API client is accurate
    - [ ] record error responses and update an required tests
    - [ ] write API documentation
- [ ] Write an eval that takes a prompt, starting program and loops until the output is correct.
  - [ ] run an eval that creates a program to calculate the first n fibonacci numbers.
  - [ ] run an eval that adds new list functions to the existing standard library.
- [ ] The output of an eval should include a realtime video of the progress of the program. Show the program as it was to the amount of time jev was thinking about it.
- [ ] Investigate the effect of the compound actions on the cost and speed of jev reaching a solution.
  - [ ] Write evals that allow you to discover better compound actions. Weigh up the cost of more options against the ability to make larger transformations for each decision
- [ ] Do deep research into the best way to use type information to guide choices.
  - Type information of all vacant nodes can be shown
  - Type information of all nodes with an effect can be shown
  - What is the best way to highlight the current selection
- [ ] Do deep research into giving jev the ability to have multiple cursors at a time.
- [ ] Do deep research into the ability to jump around the program. I think that jump to type errors is the most valuable power. but maybe there are times it doesn't work.
- [ ] Suggest and test any other improvements that will allow jev to work towards the correct solution quicker.