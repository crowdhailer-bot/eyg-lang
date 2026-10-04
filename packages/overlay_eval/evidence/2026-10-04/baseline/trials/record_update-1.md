# record_update, trial 1

Update an existing field while preserving the other fields.

Passed, score 100%.

## Checks

- **pass** computes {age: 37, name: "Ada"}: run 1 computed the value

## Turn 1

User: Run a program that changes the age in {name: "Ada", age: 36} to 37 and returns the whole record, keeping its name.

Agent: (thinking) We need to write EYG code that updates a record. We need to know syntax. Use guide to read "syntax".

Agent: (thinking) We need to write an EYG program that changes age in {name:"Ada", age:36} to 37 and returns whole record, keeping name.

The record is literal. Use record update syntax: {age: 37, ..person}. So program should define original record, then update, return.

We need to output the result. In EYG, the final expression's value is returned (to the system). Should we print? The instructions: run program that returns whole record. The tool run returns program's result? The run effect returns whatever last expression is? Likely the result will be returned to the assistant.

Thus compute:

let person = {name: "Ada", age: 36}
let updated = {age: 37, ..person}
updated

We'll just write block with let bindings and final expression.

We need to call run with code string.

Let's do that.

Agent: Ran:
```eyg
let person = {name: "Ada", age: 36}
let updated = {age: 37, ..person}
updated
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
- GET https://eyg.run/guides/eyg-syntax-guide.md 200

The agent finished.
