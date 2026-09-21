# Cursors and jumps

Where does Jev edit? Could it edit several places at once, and how should it move around the program?

## Several holes per request

A request can ask several questions, which Jev answers in parallel from the same state.
`cursors=3` uses this in hole mode: as well as the edit for the selected hole, Jev is asked what fills the next two holes.
Those holes are marked in the program, `go(«?», ⟨2:?⟩, ⟨3:?⟩)`, each question offers the edits that need no name or literal question,
and a `leave it for later` option lets Jev skip a hole it is unsure of.
The answers are applied after the main edit, each as its own step with the `AtHole(path, number, action)` action.
A hole is addressed by its path, which an edit elsewhere does not change, so the main edit adding holes does not move the others.
The tokens and time of the request are counted on the main step.
Each extra question says where its hole is and its type, as the selection description only covers the selected hole.

The `holes` sweep ran the six scaffolds three times with each variant (`sweep -- holes repeat=3`):

| Eval | holes | 2 cursors | 3 cursors | move to any hole |
| --- | --- | --- | --- | --- |
| fibonacci-scaffold | 3/3, 32 | 0/3 | 0/3 | 1/3, 21 |
| list-functions-scaffold | 1/3, 62 | 0/3 | 0/3 | 0/3 |
| greeting-scaffold | 3/3, 3 | 3/3, 3 | 3/3, 3 | 3/3, 3 |
| user-record-scaffold | 3/3, 4 | 3/3, 3 | 3/3, 3 | 3/3, 4 |
| total-scaffold | 3/3, 8 | 1/3, 52 | 1/3, 61 | 2/3, 55 |
| describe-scaffold | 3/3, 3 | 3/3, 2 | 3/3, 2 | 3/3, 3 |
| solved | 16 of 18 | 10 of 18 | 10 of 18 | 12 of 18 |
| requests | 361 | 629 | 672 | 601 |
| input tokens | 1,812,000 | 3,149,000 | 3,642,000 | 3,054,000 |

Several holes per request saves a request on the smallest tasks, `describe-scaffold` in 2 rather than 3, and fails the larger ones.
The extra answers are chosen without seeing the main edit:
in `fibonacci-scaffold` the main edit filled `!int_add(a, ?)` with `a` and the extra question filled the second argument with `a` too.
When the right edit is not offered in an extra question, `list.append(acc, [a])` needs a name question, Jev chose something close,
`acc` at 0.29 confidence, rather than leaving the hole for later.
Every wrong fill has to be found and undone, which Jev does badly, so the requests saved are spent many times over.
The same sweep before extra questions described their holes solved 9 of 18 with three cursors, describing them did not change the result.

Several cursors would need the extra answers to be conditional on the main one, a second request, which is what one cursor already is.

### Other kinds of cursor

- **The same edit in several places**, as a text editor's multiple cursors do, is mostly covered by structure:
  `rename` renames a binding and every use of it, and a compound move repeats a pattern of edits.
- **Several selections for one edit**, for example choosing the arguments of a call at once,
  is what the extra hole questions do, as each argument is a hole after `call f(?, ?)`.
- **Holes in different definitions** are the case that would gain most, `list-functions-scaffold` has one hole in `sum` and one in `last`,
  but the answers for later holes are chosen without seeing the effect of the first edit.
  Answers are only applied when the main answer is an edit, and each is checked when applied, a failed one is shown to Jev as a failed edit.

## Jumping

In whole program mode Jev can move to the next or previous node, up or down a block, to the parent,
to the next hole and to any type error. In hole mode only the next hole and type errors are offered, code does the rest.

`gleam run -m jev_playground/runs -- <since>` replays saved runs and reports how navigation was used.
Over the 544 runs of the sweeps on the final code, 19,063 steps:

- 1,328 steps, 7%, were navigation. Synthesised scripts for `eyg_packages` were 13.2% navigation, see [compound moves](./compound_moves.md).
- 1,154 of those were jumps to a type error, 128 moves to the next hole and 46 other moves.
- After a jump the next edit removed an error 379 times, left the errors 726 times and added one 35 times.
- The edit after a jump was most often `delete selection`, 183 times, then another jump, 105, `call selection(..)` and `undo`.
- 39 of the 357 solved runs jumped to an error.

Jumping to an error is the move Jev uses, and it is not enough by itself: two times in three the edit after it does not remove the error.

### When jumping to a type error does not work

- **The error is not where the mistake is.** Inference reports where unification failed.
  With arguments in the wrong order the error is on an argument, the fix is the call.
  Jev deleted the selected code after 16% of jumps, whether or not the mistake was there.
- **The error has no node.** An error inside a desugared pattern points into the IR, which the editor cannot select.
  Focusing it crashed the eval, the jump is now not offered.
- **Jumping back to repeat an edit.** Jumping to the error and wrapping it in a call, again and again, doubled a call's arguments each time.
  Moving back to repeat an edit is now stopped.
- **Errors from holes.** A hole has type `Todo`, which is not reported, so in a scaffold the errors are real ones.

### Without jumps

`nojumps` stops offering jumps to type errors, from the same 252 run sweep as [type information](./type_information.md):

| Eval | holes | holes, no jumps | whole program | whole program, no jumps |
| --- | --- | --- | --- | --- |
| fibonacci-scaffold | 2/3, 32 | 2/3, 21 | 0/3 | 0/3 |
| list-functions-scaffold | 0/3 | 0/3 | 2/3, 24 | 3/3, 43 |
| greeting-scaffold | 3/3, 3 | 3/3, 3 | 3/3, 4 | 3/3, 4 |
| user-record-scaffold | 3/3, 4 | 3/3, 4 | 3/3, 4 | 3/3, 4 |
| total-scaffold | 3/3, 8 | 3/3, 8 | 0/3 | 0/3 |
| describe-scaffold | 3/3, 3 | 3/3, 3 | 3/3, 3 | 3/3, 3 |
| solved | 14 of 18 | 14 of 18 | 11 of 18 | 12 of 18 |
| input tokens | 2,126,000 | 2,196,000 | 2,842,000 | 2,897,000 |

Taking jumps away changed nothing that three runs can show.
Jumping to a type error is not the most valuable power for Jev: after a jump its next edit removes the error only a third of the time,
and runs without jumps did as well. Where the program should go next, the next hole, matters more than where it is wrong.

### Moving to any hole

`holejumps` offers `move to hole n` for up to eight other holes, each described by where the hole is,
so Jev can fill the holes in the order the task describes them rather than reading order.
In `fibonacci-scaffold` Jev had filled the first hole with what the task gave for the second.

It solved 12 of 18 against 16 of 18 without it, see the table above.
Jev chose a move to a hole only 9 times in the 18 runs, the harm came from the options being there:
they made every request larger and shifted close calls, in `total-scaffold` Jev chose `variable item` where hole mode alone chose `select .price`.
Filling holes in reading order, with each hole described by its role, is better than offering Jev the order.

### Other jumps worth offering

- **Jump to the definition of a variable**, to change a function whose call has the error.
- **Jump to the enclosing call of an error**, as the fix for a wrong argument is often the call.
