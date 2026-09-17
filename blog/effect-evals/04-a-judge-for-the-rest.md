---
name: A judge for the rest
description: Model graded checks that stay trustworthy.
---

# A judge for the rest

Some things a value cannot settle. Whether an explanation is correct. Whether a
note is worth keeping or is noise. Whether a suggested change to Overlay names
the real cause. For those, a model reads the transcript and answers one
question.

```eyg
Judged("The agent explains that Sleep is not one of the effects programs can perform in Overlay, points to the source file that lists them, and suggests a pull request that adds Sleep. It does not claim that the program waited.")
```

Everything about how that judge is asked is chosen to keep it useful.

## One criterion per call

A judge asked to score "quality" returns a number that means nothing twice. A
judge asked whether one specific thing is true returns an answer you can argue
with. Tasks therefore carry several `Judged` checks rather than one, each
decided in its own call, and each reported separately when it fails.

## Binary, with a way out

The verdict is pass or fail, and the judge reasons before it answers. Scales
from one to five invite the middle, and the difference between a three and a
four is not stable across runs or readers.

A judge must also be able to say it cannot tell:

```
VERDICT: PASS
VERDICT: FAIL
VERDICT: UNKNOWN
```

Unknown is reported as unknown, never silently counted as a pass. A judge with
no way out will invent a reason to choose, and that reason ends up in your
numbers.

## Judge the transcript, not the conversation

The prompt contains the whole run: every program with the value it computed,
the effects that reached the environment, the workspace at the end, and why the
session stopped. So a criterion can be about what happened, not only about what
was said, and the judge is told to decide only on what the transcript shows.

The prompt also says that a short answer meeting the criterion passes. Judges
prefer longer answers, and a rubric line is a weak defence, but it is free.

## Choose a different family

Models prefer their own family's writing. The judge is configured separately
from the agent for this reason:

```sh
gleam run -m overlay/eval -- run suites/contexts.eyg \
  --model ollama:gpt-oss:120b --judge mistral:mistral-medium-latest
```

## Calibrate before you trust

A judge is a measuring instrument, and an uncalibrated instrument is a
decoration. Grade thirty trials yourself, then compare: of the trials you
passed, how many did the judge pass; of the trials you failed, how many did it
fail. Keep those two numbers apart. Raw agreement on an imbalanced set flatters
a judge that says pass to everything.

If a judge cannot be brought into line on a criterion, the criterion is
probably vague. Rewrite it as something a careful reader could check, or find a
deterministic check that covers most of it and judge only the remainder.

## Do not judge what you can check

The temptation is to write "the agent correctly worked out the id" and let a
model decide. The value is right there. Use `Computes(7)`, and spend the judge
on the sentence that explains it.
