# Videos

Runs of Jev answering DNSimple questions, from the recordings in `recordings/evals`.

| Video | What it shows |
| --- | --- |
| `one-run.mp4` | One run on its own: "What IP addresses do the A records of lovelace.dev point to?" answered in 47 edits and 15.3 seconds of thinking, the program on the left and every edit Jev chose, with its confidence and time, on the right. |
| `eighteen-runs.mp4` | The eighteen questions answered from an empty program, three at a time in a three by two grid: the six fastest, the next six, then the six longest, the last of which is a run with the readme examples turned off. |
| `overlay.mp4` | The overlay page: a question typed in, the program Jev writes, what it returned, and the list of edits opened and scrolled. |
| `run-stopped-unsure.mp4` | The same question without the readme examples: 70 edits, and the run is stopped after three choices below 0.2 confidence in a row. |
| `run-finished-wrong.mp4` | The same question again, 95 edits: Jev maps every record to its content, without the filter the question asks for, and finishes. |

`grid.html` and `one.html` play the frames, they are the pages that were recorded.
`one.html?file=<name>.json&run=<n>` plays one run and says how it ended.

```sh
gleam run -m jev_playground/frames --runtime bun -- runs.json <run> ...
```

writes the frames of each run, the program at every edit coloured by `jev_playground/highlight`.
Serve this directory, open `grid.html` or `one.html?run=0` beside `runs.json`, and record the page.
`?speed=` divides the thinking time and `?hold=` is the least time a frame is held.
The overlay video is recorded by typing questions into the page itself.
