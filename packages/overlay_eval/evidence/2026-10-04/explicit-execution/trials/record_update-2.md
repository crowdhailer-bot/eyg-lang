# record_update, trial 2

Update an existing field while preserving the other fields.

Failed, score 0%.

## Checks

- **fail** computes {age: 37, name: "Ada"}: no program computed {age: 37, name: "Ada"}, no program computed a value

## Turn 1

User: Run a program that changes the age in {name: "Ada", age: 36} to 37 and returns the whole record, keeping its name.

Agent: (thinking) We need to write an EYG program that takes a record {name: "Ada", age: 36}, modifies age to 37, returns whole record. Use syntax guide. Let's read guide for syntax.

## Effects

- GET https://eyg.run/packages/pull? 200 (loading modules)
- GET https://eyg.run/packages/pull?since=14 200 (loading modules)

The agent finished.
