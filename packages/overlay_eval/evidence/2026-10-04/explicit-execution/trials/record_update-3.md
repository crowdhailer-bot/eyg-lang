# record_update, trial 3

Update an existing field while preserving the other fields.

Passed, score 100%.

## Checks

- **pass** computes {age: 37, name: "Ada"}: run 1 computed the value

## Turn 1

User: Run a program that changes the age in {name: "Ada", age: 36} to 37 and returns the whole record, keeping its name.

Agent: (thinking) We need to write EYG script to change age field. Need to read syntax guide. Let's read guide.

Agent: (thinking) User wants: "Run a program that changes the age in {name: "Ada", age: 36} to 37 and returns the whole record, keeping its name." So we need to write EYG program that takes record, updates age, returns new record. Use record update syntax {age: 37, ..record}. So script: let person = {name: "Ada", age: 36} let updated = {age: 37, ..person} updated

We need to run using run tool. Ensure syntax correct. Use final expression as result. Let's craft code string.

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

Agent: The record with the updated age is:

{age: 37, name: "Ada"}

## Effects

- GET https://eyg.run/packages/pull? 200 (loading modules)
- GET https://eyg.run/packages/pull?since=14 200 (loading modules)
- GET https://eyg.run/guides/eyg-syntax-guide.md 200

The agent finished.
