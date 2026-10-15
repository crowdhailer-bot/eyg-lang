# record_update, trial 3

Update an existing field while preserving the other fields.

Passed, score 100%.

## Checks

- **pass** computes {age: 37, name: "Ada"}: run 1 computed the value

## Turn 1

User: Run a program that changes the age in {name: "Ada", age: 36} to 37 and returns the whole record, keeping its name.

Agent: (thinking) We need to write an EYG program that updates the record. Use record update syntax: {age: 37, ..person}. So let person = {name: "Ada", age: 36} then let updated = {age: 37, ..person} then final expression updated.

We need to run via functions.run. Return final expression. No need for Print. Let's do that.

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

Agent: The updated record is `{age: 37, name: "Ada"}`.

## Effects

- GET https://eyg.run/packages/pull? 200 (loading modules)
- GET https://eyg.run/packages/pull?since=14 200 (loading modules)

The agent finished.
