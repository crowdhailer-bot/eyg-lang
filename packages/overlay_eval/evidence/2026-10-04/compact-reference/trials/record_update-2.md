# record_update, trial 2

Update an existing field while preserving the other fields.

Passed, score 100%.

## Checks

- **pass** computes {age: 37, name: "Ada"}: run 2 computed the value

## Turn 1

User: Run a program that changes the age in {name: "Ada", age: 36} to 37 and returns the whole record, keeping its name.

Agent: (thinking) We need to write an EYG program that updates record. Use let person = {name:"Ada", age:36}; then let updated = {age:37, ..person}; then final expression updated. Should return whole record with name unchanged. Use run tool.

Agent: Ran:
```eyg
let person = {name: "Ada", age: 36} ; {age: 37, ..person}
```
Result: invalid code
```
error: invalid character ';' at position 36
hint: remove or replace this character — EYG does not use it

 1 | let person = {name: "Ada", age: 36} ; {age: 37, ..person}
                                         ^
```

Agent: (thinking) We need correct syntax: let name = value is separate lines, but program is expression. Should do: let person = {name: "Ada", age: 36} in expression? The reference: "Programs are expressions. A sequence is let name = value followed by a final expression." Probably newline separates. Use newline or just separate with space? Use line break. Let's try:

let person = {name: "Ada", age: 36}
{age: 37, ..person}

Agent: Ran:
```eyg
let person = {name: "Ada", age: 36}
{age: 37, ..person}
```
Result: computed
```
{age: 37, name: "Ada"}
```

Agent: The updated record is:

{age: 37, name: "Ada"}

## Effects

- GET https://eyg.run/packages/pull? 200 (loading modules)
- GET https://eyg.run/packages/pull?since=14 200 (loading modules)

The agent finished.
