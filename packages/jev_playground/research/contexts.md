# Contexts

Can Jev answer questions about a person's DNSimple account from an empty program, with no scaffold,
given only the overlay context for DNSimple?

## The context

An overlay context is an EYG module in scope as `context` for every program, with a `readme` that describes it.
`eyg_packages/dnsimple/index.eyg` is the DNSimple context, and it assumes as little as it can:

- One function for each endpoint of the API, named as DNSimple names the operation: `whoami`, `list_domains`,
  `get_domain`, `list_zone_records`, `get_zone_record`, `create_zone_record`, `update_zone_record`,
  `delete_zone_record`, `check_domain`, `get_domain_delegation`, `enable_domain_auto_renewal` and
  `disable_domain_auto_renewal`. Nothing is rolled up, nothing is guessed at:
  changing a record means finding its id in the records of the zone first, as it does with the API itself.
- No list helpers of its own. A program works on lists with `@standard`, which Jev opens for itself.
- Its own JSON decoders, those of `@json`, over the `DecodeJSON` effect, so it references no other module.
  The hub type checks every module it is given and a context with no references can be shared as one block.
- Every call performs `DNSimple` with an operation, the platform adds the token and the account id,
  as the CLI and the overlay do.
- A failed call aborts with the message DNSimple gives, `Zone \`lovelace.com\` not found`.

It is shared to the local hub, which stores modules in Postgres, and referenced by content id:

```sh
EYG_ORIGIN=http://localhost:8080 eyg share eyg_packages/dnsimple/index.eyg
# baguqeerassuttu4yl3zupjf6v54e2d4ynkvaygsfsucm6z6siwspnsbmfyuq
```

The evals fetch the context from the hub by that id, `EYG_HUB` sets which hub, and a test checks the module in
the repository has that id. Programs run against an account served from memory, `jev_playground/dnsimple`,
which answers the API's endpoints and remembers what a program changed, so a checker can look at the account
afterwards.

## Pulling a library

The context has no `count` or `map`, so a question about more than one record needs `@standard`.
Jev reaches it in three ways, none of which it could do before this work:

- `open library @standard` is an edit like any other. The library's API then appears in the state.
- A library the program already references counts as open, so code that comes in with a readme example
  brings its API with it.
- The functions of an open library are offered as compound moves, exactly as the context's are:
  `call @standard.list.filter(predicate, haystack)`, `wrap in @standard.list.map(.., f)` and the function
  itself where one is expected. They are offered in hole mode only, where the type filter keeps the list short,
  and at most forty per library, the functions that shape data first.
- A release is written `@standard:1:baguq…` in the tree and read as `@standard` everywhere a person or Jev
  sees it. Code Jev inserts is pinned as it is parsed.

`wrap in @standard.list.map(.., f)` needs an edit that passes the selection as the first argument of a call
taking more than one, which `morph` did not have.

## Thirty one questions

The questions are what a person would ask of their own account, easiest first, and none of them names a
context function. Every run starts from `?`, in hole mode and blind: Jev is told what each complete program
returns, never whether it is right, and the answer is the program it finishes with (`sweep -- default dnsimple`).

Eighteen are answered, at $0.0016 and six edits each on average:

| Question | Edits | Cost |
| --- | --- | --- |
| What domains are in my DNSimple account? | 2 | $0.0003 |
| List every DNS record in my account. | 2 | $0.0004 |
| Turn on auto-renew for notes.garden. | 3 | $0.0005 |
| Which name servers is notes.garden delegated to? | 3 | $0.0005 |
| How many DNS records does lovelace.dev have? | 3 | $0.0006 |
| List the DNS records of analytical.engineering. | 3 | $0.0005 |
| How many DNS records do I have across all of my domains? | 3 | $0.0006 |
| Is jev-rocks.com available to register? | 4 | $0.0007 |
| What email address is my account registered to? | 4 | $0.0006 |
| What plan is my DNSimple account on? | 4 | $0.0006 |
| How many domains do I have? | 7 | $0.0020 |
| Delete the TXT record named "old" from lovelace.dev. | 7 | $0.0016 |
| Add an MX record to notes.garden pointing at mail.notes.garden. | 8 | $0.0014 |
| Add a TXT record to lovelace.dev with the content "google-site-verification=abc123". | 8 | $0.0014 |
| Point www.notes.garden at 203.0.113.7 with an A record. | 8 | $0.0014 |
| What are the MX records of analytical.engineering? | 13 | $0.0035 |
| What IP addresses do the A records of lovelace.dev point to? | 17 | $0.0046 |
| When does notes.garden expire? | 22 | $0.0036 |

Thirteen are not: `no-renew`, `expiring`, `a-count`, `change-api`, `ttl-total`, `busiest`, `cname-hosts`,
`www-everywhere`, `drop-txt`, `unregistered`, `api-ttl`, `remove-blog` and `mail-hosts`.
They fail in two ways. Either the program needs a shape no readme example has, a fold or a match on a
boolean field, and Jev wanders until the edits run out; or it writes a program that returns something
plausible and finishes, `map` over every record without the `filter` that the question asked for.

The readme examples are what make the short runs short. The same question without them takes the long way:
`record-count` is three edits with the examples and thirty eight without, `sweep -- default` against
`evaluate -- dnsimple-record-count holes blind ctx=calls`.

## What the reduction cost

The context before this work had `records`, `record_values`, `expiring_before`, `without_auto_renew`,
`count`, `map`, `filter`, `flatten`, and it took a host wherever it took a domain.
Every one of the twenty questions was answered, three times each, in four edits on average.
One function per endpoint costs eighteen of thirty one, and the programs are three times longer.

The difference is not Jev's: it is how much of the question the context had already answered.
`context.without_auto_renew({})` is one edit; the same answer from `list_domains` is a filter over a boolean
field inside a lambda, which is where the runs that fail now fail.
A context is a design surface, and the trade is between a library shaped like the questions
and one shaped like the API.

## Showing effects

Measured with the context before the reduction, over its twenty questions.
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

Measured with the context before the reduction. A compound move is a series of edits offered as one option. The functions of the context can be offered as calls in several ways,
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

Measured with the context before the reduction, each left out in turn (`sweep -- without repeat=3 dnsimple`):

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

- A wrap such as `wrap in context.flatten(..)` left `context.flatten`, a function, selected, so the next wrap
  made `context.count(context.flatten)(..)`. A wrap now ends on the call.
- `context.records` given to `map` stayed selected to be called, a function filling a hole that expects a
  function is now finished.
- No values are offered for a complete program, which is selected whole in hole mode and a value would replace
  it, but that also removed `select .email`, so the program returned the whole account.
  Edits that build on the selection are kept.
- A complete program could not be changed in part. Each argument of a call can now be selected by its code,
  `select "api.lovelace.dev"`, and only literals are offered: jumping into a lambda sent runs into a loop.
- An edit waiting for text was offered when its question had no candidates, and the run failed with
  "no answer to the label question". Strings and integers were never asked for in their own question at all.
- The program Jev read was mostly content ids, `@standard:1:baguqeera…` at every use of the library.

Asking Jev separately whether the program's output answers the task, rather than leaving `finish` among the
edits, was measured and dropped: it stopped at the whole account record for "what email address" and at every
record for "which mail servers", `answered` turns it back on.

## Designing the context

Two things in the context pay for themselves, and both are documentation rather than code:

- The examples in the readme are offered as compound moves with their strings as holes. `total-records` and
  `every-record` went from never solved to two and three edits once an example showed `flat_map` over the
  domains, and the delete-by-name example is what carries `remove-old`. A question shaped like an example is
  nearly free, so the examples decide as much as the functions do.
- A line of prose is worth a run: "answer with only what is asked, select the field of a record" took
  `plan` and `email` from finishing with the whole account to four edits.

The lesson from the context before the reduction still stands where a context does roll things up: Jev wrote
`api.lovelace.dev` as the domain in every run, whatever the readme said, so that context resolved a host to
its zone rather than teaching the model the API's shape.

## On the overlay page

The overlay page answers questions the same way, with the person's own key.
Jev is a provider beside the language models, `?reference=<cid>` loads the context from the hub, the libraries
a program may reference are fetched at the start, and requests go to `/v1` on the page's origin, which
forwards them to TypeSafe, as browsers are refused by CORS.
DNSimple calls go through the Spotless OAuth proxy, the token kept in session storage.
A question is given up after eighty requests or three unsure choices in a row.

What Jev writes is shown as it writes it: coloured by the same highlighter the playground uses, wrapped to the
width of the chat, releases written as `@standard`, and under the answer a list of every edit with its
confidence and the time Jev took, which opens and scrolls.

## Videos

`jev_playground/frames` replays saved runs into the frames of a video: for each edit the program as it stood,
coloured by the shared highlighter, with the time Jev took. A page in `tmp` plays eighteen of them in a
three by two grid, the fastest six first and the longest six last, and Playwright records it.
The overlay video is recorded the same way, by typing questions into the page.
Both are in `tmp`, which is not committed.
