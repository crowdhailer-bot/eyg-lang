# Videos

Runs of Jev answering DNSimple questions, from the recordings in `recordings/evals`.

| Video | What it shows |
| --- | --- |
| `one-run.mp4` | One run on its own: "What IP addresses do the A records of lovelace.dev point to?" answered in 47 edits and 15.3 seconds of thinking, the program on the left and every edit Jev chose, with its confidence and time, on the right. |
| `eighteen-runs.mp4` | The eighteen questions answered from an empty program, three at a time in a three by two grid: the six fastest, the next six, then the six longest, the last of which is a run with the readme examples turned off. |
| `overlay.mp4` | The overlay page: a question typed in, the program Jev writes, what it returned, and the list of edits opened and scrolled. |

`grid.html` and `one.html` play the frames, they are the pages that were recorded.

```sh
gleam run -m jev_playground/frames --runtime bun -- runs.json <run> ...
```

writes the frames of each run, the program at every edit coloured by `jev_playground/highlight`.
Serve this directory, open `grid.html` or `one.html?run=0` beside `runs.json`, and record the page.
`?speed=` divides the thinking time and `?hold=` is the least time a frame is held.
The overlay video is recorded by typing questions into the page itself.
