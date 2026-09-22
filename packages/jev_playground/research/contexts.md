# Contexts

Can Jev answer questions about a person's DNSimple account from an empty program, with no scaffold,
given only the overlay context for DNSimple?

## The context

An overlay context is an EYG module in scope as `context` for every program, with a `readme` that describes it.
`eyg_packages/dnsimple/index.eyg` is the DNSimple context:

- Functions shaped like the questions people ask: `domain_names({})`, `records(domain)`, `record_values(domain, type)`,
  `expiring_before(date)`, `add_record(domain, name, type, content)` and a dozen more, each returning plain values.
  A host such as `api.lovelace.dev` can be given wherever a domain is.
- List helpers, `count`, `sum`, `map`, `filter` and `flatten`, as a program cannot reference `@standard` without a
  dependency the context does not have.
- Its own JSON decoders, those of `@json`, over the `DecodeJSON` effect, so it references no other module.
  The hub type checks every module it is given and a context with no references can be shared as one block.
- Every call performs `DNSimple` with an operation, the platform adds the token, as the CLI and the overlay do.

It is shared to the local hub, which stores modules in Postgres, and referenced by content id:

```sh
EYG_ORIGIN=http://localhost:8080 eyg share eyg_packages/dnsimple/index.eyg
# baguqeeravurubercfnyuz5qixlxmozbf5qbm77izd45d6hkheoul73j463xa
```

The evals fetch the context from the hub by that id, `EYG_HUB` sets which hub, and a test checks the module in the repository has that id.
Programs run against an account served from memory, `jev_playground/dnsimple`, which answers the API's endpoints
and remembers what a program changed, so a checker can look at the account afterwards.

## Twenty questions

| # | Question | A program that answers it |
| --- | --- | --- |
| 1 | What domains are in my DNSimple account? | `context.domain_names({})` |
| 2 | How many domains do I have? | `context.count(context.domain_names({}))` |
| 3 | What email address is my account registered to? | `context.account({}).email` |
| 4 | Is jev-rocks.com available to register? | `context.is_available("jev-rocks.com")` |
| 5 | Which name servers is notes.garden delegated to? | `context.name_servers("notes.garden")` |
| 6 | List the DNS records of analytical.engineering. | `context.records("analytical.engineering")` |
| 7 | How many DNS records does lovelace.dev have? | `context.count(context.records("lovelace.dev"))` |
| 8 | What IP addresses do the A records of lovelace.dev point to? | `context.record_values("lovelace.dev", "A")` |
| 9 | What are the MX records of analytical.engineering? | `context.records_of_type("analytical.engineering", "MX")` |
| 10 | Which of my domains will not renew automatically? | `context.without_auto_renew({})` |
| 11 | When does notes.garden expire? | `context.domain("notes.garden").expires_on` |
| 12 | Which of my domains expire before 2027-06-01? | `context.expiring_before("2027-06-01")` |
| 13 | How many A records does lovelace.dev have? | `context.count(context.records_of_type("lovelace.dev", "A"))` |
| 14 | Add a TXT record to lovelace.dev with the content "google-site-verification=abc123". | `context.add_record("lovelace.dev", "", "TXT", "google-site-verification=abc123")` |
| 15 | Point www.notes.garden at 203.0.113.7 with an A record. | `context.add_record("notes.garden", "www", "A", "203.0.113.7")` |
| 16 | Delete the TXT record named "old" from lovelace.dev. | `context.remove_record("lovelace.dev", "old", "TXT")` |
| 17 | Turn on auto-renew for notes.garden. | `context.enable_auto_renew("notes.garden")` |
| 18 | Change the A record of api.lovelace.dev to 198.51.100.4. | `context.change_record("lovelace.dev", "api", "A", "198.51.100.4")` |
| 19 | How many DNS records do I have across all of my domains? | `context.count(context.flatten(context.map(context.domain_names({}), context.records)))` |
| 20 | List every DNS record in my account. | `context.flatten(context.map(context.domain_names({}), context.records))` |

Every run starts from `?`. Questions 14 to 18 change the account and are checked by looking at it afterwards,
the others by what the program returns. Jev is told what its program returned, not the answer.

## From an empty program

Every question was run three times with each way of showing effects, in hole mode and blind:
Jev is told what each new complete program returns, never whether it is right, and the answer is the program it finishes with,
as on the overlay page (`sweep -- final repeat=3 dnsimple`).

| # | Question | Steps |
| --- | --- | --- |
| 1 | domains | 2 |
| 2 | domain-count | 3 |
| 3 | email | 3 |
| 4 | available | 3 |
| 5 | name-servers | 3 |
| 6 | records | 3 |
| 7 | record-count | 4 |
| 8 | a-records | 4 |
| 9 | mx | 4 |
| 10 | no-renew | 2 |
| 11 | expiry | 4 |
| 12 | expiring | 3 |
| 13 | a-count | 5 |
| 14 | add-txt | 6 |
| 15 | point-www | 6 |
| 16 | remove-old | 5 |
| 17 | auto-renew | 3 |
| 18 | change-api | 6 |
| 19 | total-records | 2 |
| 20 | every-record | 6 |

Every run of a question took the same steps, finishing included. They are the steps of the defaults:
only `total-records` differs between strategies, nine steps where the readme examples are not offered.
With the defaults, 60 of 60 runs solved for $0.039, 1.6 seconds and $0.00065 a question.
One request in 300 timed out, the only failure of the sweep that compared the ways of showing effects.

## Showing effects

`effect_at` in `eyg_analysis` gives the effects a node performs, so the state can say what each call does.
Every effect of a context is reached through its functions, so how effects are shown decides cost more than success:

| Effects | Solved | Tokens | Cost of 60 runs |
| --- | --- | --- | --- |
| `hidden`, not listed or offered | 60 | 964,000 | $0.041 |
| `signatures`, listed and offered to perform or handle | 59, one timeout | 1,547,000 | $0.065 |
| `calls`, signatures and each context call offered says what it performs | 60 | 1,606,000 | $0.067 |
| `nodes`, calls and what the program and selection perform, in the state | 60 | 1,609,000 | $0.068 |
| `callsonly`, only each context call offered says what it performs | 60 | 998,000 | $0.042 |

The `mx` runs were checked again after the checker accepted the mail servers as well as the records, 15 of 15.
Before the fixes below, with the verdict shown to Jev, `hidden` solved 55, `calls` 54 and `callsonly` 55 of 60, `change-api` none.
The overlay shows effects on context calls only, as cheap as hiding them and it still says which calls change the account.

## Compounds from the context

A compound move is a series of edits offered as one option. The functions of the context can be offered as calls in several ways,
each run blind three times over the twenty questions (`sweep -- strategies repeat=3 dnsimple`):

| Strategy | What is offered | Solved of 60 | Tokens | Cost |
| --- | --- | --- | --- | --- |
| `none` | the context is a variable, selected from and called in separate steps | 16 | 8,222,000 | $0.345 |
| `bare` | `call context.records(?)`, a hole for each input | 53 | 2,352,000 | $0.099 |
| `unit` | and `context.domains({})` for a function that ignores its input | 57 | 2,184,000 | $0.092 |
| `calls` | `call context.records(domain)`, named by its parameters, and wraps | 59 | 1,573,000 | $0.066 |
| `chains` | and one function called with the result of another where it fits | 60 | 2,322,000 | $0.098 |
| `examples` | and the examples in the readme with their strings as holes | 60 | 1,463,000 | $0.062 |

- Without compounds Jev has to select from `context`, call the result and fill it, and 44 of 60 runs never got there.
  The context is what makes an empty program tractable, but only if its functions are offered as calls.
- Parameter names are worth a run or two: they name the argument in the option, `call context.change_record(domain, name, type, content)`,
  and the hole's role, "argument 1 of 4, `domain`".
- Chains solve everything and cost half as much again, every pairing that type checks is another option on every request.
- Examples are the readme's code blocks with their literals as holes. A question shaped like an example takes two steps rather than nine,
  which is the context author teaching an idiom, and a reason to write examples into a readme. It is the default.
- The one failure with `calls` was `total-records`, where the parameter of the function given to `map` was named `_`,
  so nothing could reference the item. `_` is offered first as it is usually useful, and in a lambda it usually is not.

## The readme and argument jumps

With the defaults, examples and effects on calls only, each left out in turn (`sweep -- without repeat=3 dnsimple`):

| | Solved of 60 | Tokens | Cost |
| --- | --- | --- | --- |
| the defaults | 60 | 933,000 | $0.039 |
| `noreadme`, the readme left out of the state | 58 | 944,000 | $0.040 |
| `noargjumps`, no selecting an argument of a complete program | 60 | 933,000 | $0.039 |

The readme is worth two runs even when its examples are still offered as compounds.
Offered as prose alone, before the examples became the default, it was worth five: 60 of 60 against 55, with a third fewer tokens,
`every-record` failing every time without it.
Argument jumps cost nothing and are no longer needed now that the context takes a host, they took `total-records` from twelve steps to nine.

## What blind runs found

Most failures were the harness rather than Jev, each fixed with a test in `dnsimple_test`:

- A wrap such as `wrap in context.flatten(..)` left `context.flatten`, a function, selected, so the next wrap made `context.count(context.flatten)(..)`.
  A wrap now ends on the call.
- `context.records` given to `map` stayed selected to be called, a function filling a hole that expects a function is now finished.
- No values are offered for a complete program, which is selected whole in hole mode and a value would replace it,
  but that also removed `select .email`, the program returned the whole account. Edits that build on the selection are kept.
- A complete program could not be changed in part. Each argument of a call can now be selected by its code, `select "api.lovelace.dev"`.

`total-records`, `every-record`, `email` and `expiry` went from 0 of 15 blind runs each to 15 of 15.

## Designing the context

"Change the A record of api.lovelace.dev" failed in every run, Jev passed `api.lovelace.dev` as the domain at 0.8 or more.
It still did with the host rule in the readme, with an example, with the API's own error, `Zone \`api.lovelace.dev\` not found`, and with a way to change one argument.
Offering the parts of a host before the host moved the choice from 0.78 to 0.55, not enough.
The context now places a host in the domain of the account it belongs to, a record name is relative to the host,
and the host's own label given again means the host. `change-api` went from 0 of 12 to 12 of 12.
A context for Jev should accept what the model writes rather than teach it the API.

Failed calls now abort with the message DNSimple gives rather than a status code,
and the readme shows selecting a field, `context.account({}).email`.

## On the overlay page

The overlay page answers questions the same way, with the person's own key.
Jev is a provider beside the language models, `?reference=<cid>` loads the context from the hub,
and requests go to `/v1` on the page's origin, which forwards them to TypeSafe, as browsers are refused by CORS.
DNSimple calls go through the Spotless OAuth proxy, the token kept in session storage.
A question is given up after 30 requests or three unsure choices in a row, and the person is asked to put it another way.

The page shows Jev what each new complete program returned and answers with the program it finishes with,
which is the `blind` protocol of these evals.
