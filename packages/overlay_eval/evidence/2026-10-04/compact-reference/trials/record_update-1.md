# record_update, trial 1

Update an existing field while preserving the other fields.

Passed, score 100%.

## Checks

- **pass** computes {age: 37, name: "Ada"}: run 2 computed the value

## Turn 1

User: Run a program that changes the age in {name: "Ada", age: 36} to 37 and returns the whole record, keeping its name.

Agent: (thinking) We need to write EYG program: let person = {name: "Ada", age: 36}; update age to 37 keeping name: {age: 37, ..person} but that will keep other fields (name) and overwrite age. Then final expression should be the new record. So program is: let person = {name: "Ada", age: 36} in {age: 37, ..person}. Need to use run tool.

Agent: Ran:
```eyg
let person = {name: "Ada", age: 36} in {age: 37, ..person}
```
Result: invalid code
```
error: unexpected `{` at position 39 — the expression is complete but there are leftover tokens
hint: EYG uses function calls for operations (e.g. !int_add(a, b)), not infix operators

 1 | let person = {name: "Ada", age: 36} in {age: 37, ..person}
                                            ^
```

Agent: (thinking) We need proper syntax: let name = value in expr. The record update syntax shown: {age: 37, ..person}. That's fine. But need parentheses perhaps? Actually code: let person = {name: "Ada", age: 36} in {age: 37, ..person}. The parser thinks leftover tokens after closing? Maybe need semicolon? The quick reference: sequence is let name = value followed by a final expression. Might need newline? Perhaps use let person = {name: "Ada", age: 36} ; {age: 37, ..person}. But syntax may be let ... in ... is okay. The error at position 39: after person}. Let's count: "let person = {name: \"Ada\", age: 36} in {age: 37, ..person}" The parser maybe doesn't support .. spread? The guide might clarify. Let's request guide for syntax.

Agent: (thinking) We need to write an EYG program to change the age field to 37, keeping name, returning whole record. We attempted using record update {age:37, ..person} but error said unexpected `{` token at position 39 meaning syntax maybe expects let block with two expressions: let person = {...} person? Actually let syntax: let name = value expression? In guide: "let" binds a value to a name. In a block, multiple lets written on successive lines. At top-level, you can have multiple let statements then final expression. So we need program:

let person = {name: "Ada", age: 36}
{age: 37, ..person}

But need a final expression after let, not with 'in'. So try:

let person = {name: "Ada", age: 36}
{age: 37, ..person}

Let's run.

Agent: Ran:
```eyg
let person = {name: "Ada", age: 36}
{age: 37, ..person}
```
Result: computed
```
{age: 37, name: "Ada"}
```

Agent: The record with the updated age is:

{age: 37, name: "Ada"}

## Effects

- GET https://eyg.run/packages/pull? 200 (loading modules)
- GET https://eyg.run/packages/pull?since=14 200 (loading modules)
- GET https://eyg.run/guides/eyg-syntax-guide.md 200

The agent finished.
