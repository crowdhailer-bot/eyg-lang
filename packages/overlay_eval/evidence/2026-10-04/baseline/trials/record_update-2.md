# record_update, trial 2

Update an existing field while preserving the other fields.

Passed, score 100%.

## Checks

- **pass** computes {age: 37, name: "Ada"}: run 1 computed the value

## Turn 1

User: Run a program that changes the age in {name: "Ada", age: 36} to 37 and returns the whole record, keeping its name.

Agent: (thinking) We need to write an EYG program that modifies a record. We need to know EYG syntax; not given yet. Use guide.

Agent: (thinking) We need to write an EYG script that manipulates a record. Need to read syntax guide first.

Agent: (thinking) We need to run a program that changes the age in {name: "Ada", age: 36} to 37, returning whole record, keeping name. Use EYG. We need to output result. We'll write EYG expression that creates record, updates age.

Record: {name: "Ada", age: 36}. Want to produce {age: 37, ..record}. Should return whole record.

We can write code:

let person = {name: "Ada", age: 36}
{age: 37, ..person}

That's final expression. No effects needed.

We need to run with run effect. Use functions.run with code string. Let's produce.

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
- GET https://eyg.run/guides/eyg-syntax-guide.md 200

The agent finished.
