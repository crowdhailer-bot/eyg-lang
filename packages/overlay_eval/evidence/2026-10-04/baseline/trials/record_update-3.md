# record_update, trial 3

Update an existing field while preserving the other fields.

Passed, score 100%.

## Checks

- **pass** computes {age: 37, name: "Ada"}: run 1 computed the value

## Turn 1

User: Run a program that changes the age in {name: "Ada", age: 36} to 37 and returns the whole record, keeping its name.

Agent: (thinking) We need to write an EYG program to change age from 36 to 37 in a record. The context says we have a variable scope with a module described in the Context. Not provided details, but we can assume we have the record {name: "Ada", age: 36}. Need to change age to 37 and return whole record.

We need to read the syntax guide. Use guide tool.

Agent: (thinking) The user wants a program that changes the age in {name: "Ada", age: 36} to 37 and returns the whole record, keeping name. So need to write EYG script: let person = {name:"Ada", age:36}; let updated = {age:37, ..person}; updated. Return updated record.

We need to read syntax guide already done. We'll produce a script with maybe let. Return record as final expression.

We need to run it using run tool. Use code string.

We should check result. Let's construct code:

```
let person = {name: "Ada", age: 36}
let updated = {age: 37, ..person}
updated
```

That returns the record.

Run.

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

Agent: The program updated the record successfully and returned:

{age: 37, name: "Ada"}

## Effects

- GET https://eyg.run/packages/pull? 200 (loading modules)
- GET https://eyg.run/packages/pull?since=14 200 (loading modules)
- GET https://eyg.run/guides/eyg-syntax-guide.md 200

The agent finished.
