# record_update, trial 1

Update an existing field while preserving the other fields.

Passed, score 100%.

## Checks

- **pass** computes {age: 37, name: "Ada"}: run 1 computed the value

## Turn 1

User: Run a program that changes the age in {name: "Ada", age: 36} to 37 and returns the whole record, keeping its name.

Agent: (thinking) We need to write an EYG program that modifies the record. Syntax unknown; need to read guide.

Agent: (thinking) We need to run a program that takes record {name: "Ada", age: 36}, changes age to 37, returns full record. Use record update syntax {age: 37, ..record}. Need to bind original then produce updated.

EYG script: let person = {name: "Ada", age: 36} {age: 37, ..person}

Thus final expression returns record.

We must run via run tool.

Agent: Ran:
```eyg
let person = {name: "Ada", age: 36} {age: 37, ..person}
```
Result: computed
```
{age: 37, name: "Ada"}
```

Agent: The record with the age updated to 37 is:

{age: 37, name: "Ada"}

## Effects

- GET https://eyg.run/packages/pull? 200 (loading modules)
- GET https://eyg.run/packages/pull?since=14 200 (loading modules)
- GET https://eyg.run/guides/eyg-syntax-guide.md 200

The agent finished.
