# Erlang counter demo video

[Watch the video](erl-counter.mp4), or open [the local player](index.html).

The 69-second silent video shows an actual Erlang/OTP 28 session:

| Time | Action |
| --- | --- |
| 0:00 | Build and start the application on a named Erlang node |
| 0:09 | Connect a second node with `erl -remsh` |
| 0:17 | Type an EYG script using `@standard.list.map` |
| 0:31 | Check it; the hub dependency loads silently |
| 0:50 | Run it using the retained cache, then inspect the counters |

The hub is the real `https://eyg.run`. The recording starts with a fresh application
and empty session cache. It shows `cached` changing from `false` to `true` after
checking, while `supervisor:which_children` still returns `[]`. Running the script
then starts `apples`, `pears`, and `plums`, ticking once per second.

Typing is automated; terminal output and timings are captured from the real PTY.
The MP4 adds chapter headings and explanatory captions around that recording.
The original recording is [erl-counter.cast](erl-counter.cast) (asciicast v2),
with [raw terminal output](session.txt) and [chapter timings](chapters.json).

## Why the shell uses a session

[`counters_session`](../src/counters_session.erl) is a small `gen_server` that
keeps the cache returned by `counters_eyg:check/2` and `run/2` in its state.
Only the type or execution result is returned to the remote shell. This avoids
copying the large interpreter cache into the interactive shell's bindings, which
stalled the OTP 28 remote shell during recording. The explicit cache-returning
API remains the same; the session demonstrates how an application owns it.

```erlang
{ok, Session} = counters_session:start_link().
{ok, Type} = counters_session:check(Session, Script).
{ok, Value} = counters_session:run(Session, Script).
```

## Record again

Run from `examples/erl_counter`. Requires Erlang, Gleam, Python 3.10+, `uv`, and
the DejaVu Sans Mono font. Python dependencies and the FFmpeg binary are installed
under the example's ignored `build` directory:

```sh
UV_CACHE_DIR=build/video-uv-cache uv venv build/video-venv
UV_CACHE_DIR=build/video-uv-cache uv pip install \
  --python build/video-venv/bin/python -r video/requirements.txt
build/video-venv/bin/python -u video/record.py
```

The recorder builds the application, starts `eyg_counters_video`, connects
`eyg_shell_video`, and stops its nodes afterward. It checks the actual command
results before rendering. It uses the current user's Erlang cookie, without
displaying or recording it.

Outputs are written here, in `examples/erl_counter/video`. To re-render an existing
capture without starting nodes or fetching packages:

```sh
build/video-venv/bin/python video/record.py --render-only
```

The video is H.264 MP4, 1600×1008, 15 fps, with fast-start metadata for playback.

## Observer video

[erl-counter-observer.mp4](erl-counter-observer.mp4) is an 80-second silent recording of a real session:

| Time | Action |
| --- | --- |
| 0:00 | Start the application on a named node, join it with `erl -remsh` |
| 0:15 | Start a `counters_session` and open Observer on the application node |
| 0:25 | A single effect, `StartCounter("apples")` |
| 0:30 | A type error, `StartCounter(1)`, found before anything runs |
| 0:35 | Several effects, starting `pears` and setting it to tick every second |
| 0:45 | Inspect a counter's state in Observer |
| 0:55 | `@standard.list.map` starts four more counters, the library is fetched from the hub |
| 1:15 | Read the value of `pears` |

The results are printed with a small shell function that renders EYG values with
`eyg@interpreter@simple_debug:inspect/1`.

Record it again from `examples/erl_counter`, this needs Xvfb, openbox, xterm, xdotool and ffmpeg:

```sh
video/record_observer.sh
```

`video/record_observer.sh --dry` writes screenshots to `build/observer-shots` instead of a video.
The recorder starts and stops its own display and nodes.
