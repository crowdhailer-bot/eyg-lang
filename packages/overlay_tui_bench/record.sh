#!/usr/bin/env bash
# Record the real CLI in an isolated X display and tmux session.
# Uses an existing Codex login through the checked-in example; never writes it.
set -euo pipefail
cd -- "$(dirname -- "$0")/../.."
session=eyg-tui-record
record_tmp=$(mktemp -d)
xvfb_pid=
xterm_pid=
record_pid=
cleanup() {
  if [[ -n "$record_pid" ]]; then kill -INT "$record_pid" 2>/dev/null || true; wait "$record_pid" 2>/dev/null || true; fi
  tmux kill-session -t "$session" 2>/dev/null || true
  if [[ -n "$xterm_pid" ]]; then kill "$xterm_pid" 2>/dev/null || true; fi
  if [[ -n "$xvfb_pid" ]]; then kill "$xvfb_pid" 2>/dev/null || true; fi
  rm -rf -- "$record_tmp"
}
trap cleanup EXIT
Xvfb :98 -screen 0 1400x900x24 -nolisten tcp > "$record_tmp/xvfb.log" 2>&1 &
xvfb_pid=$!
sleep 1
tmux new-session -d -s "$session" -x 110 -y 34 -c "$PWD"
tmux set-option -t "$session" status off
DISPLAY=:98 xterm -geometry 110x34+0+0 -fa 'DejaVu Sans Mono' -fs 14 -bg '#141414' -fg '#eeeeee' -b 2 -e tmux attach-session -t "$session" > "$record_tmp/xterm.log" 2>&1 &
xterm_pid=$!
sleep 1
key() { tmux send-keys -t "$session" "$@"; }
type_text() { tmux send-keys -t "$session" -l "$1"; }
submit() { type_text "$1"; sleep 1; key Enter; sleep 2; }
record() {
  ffmpeg -hide_banner -loglevel error -f x11grab -draw_mouse 0 -framerate 20 -video_size 1324x820 -i :98+0,0 -c:v libx264 -threads 2 -preset veryfast -crf 22 -pix_fmt yuv420p -movflags +faststart -y "$1" > "$record_tmp/ffmpeg.log" 2>&1 &
  record_pid=$!
}
finish() {
  kill -INT "$record_pid"
  wait "$record_pid" || true
  record_pid=
  key C-c
  sleep 1
}
for variant in core signals lustre; do
  package="packages/overlay_tui_${variant}"
  mkdir -p "$package/recordings"
  submit "bun $package/entry.mjs"
  sleep 2
  record "$package/recordings/repl.mp4"
  sleep 1
  submit '!int_add(20, 22)'
  submit 'let answer = 40'
  submit '!int_add(answer, 2)'
  submit 'perform StandardOut("Hello from Gleam\n")'
  key C-e; sleep 3
  submit '/type answer'
  type_text '!int_add(20, 22)'; sleep 1
  key F2; sleep 1
  key Right; sleep 0.3
  key Right; sleep 0.3
  type_text n; sleep 1
  type_text 40; sleep 1
  key Enter; sleep 2
  type_text z; sleep 1
  type_text Z; sleep 2
  key Enter; sleep 3
  finish
  submit "bun $package/entry.mjs overlay packages/overlay_tui/examples/codex.eyg"
  sleep 2
  record "$package/recordings/overlay.mp4"
  submit 'Use the run tool once: print "Hello from Gleam" with StandardOut, then calculate !int_add(20, 22). Finish with one short sentence explaining the result.'
  # Wait on actual UI completion, with a bounded provider timeout.
  for attempt in $(seq 1 90); do
    pane=$(tmux capture-pane -p -t "$session")
    if [[ "$pane" == *"Ready"* && "$pane" == *"run"* && "$pane" != *"Running…"* ]]; then break; fi
    sleep 1
  done
  sleep 2
  key C-o; sleep 4
  key C-e; sleep 4
  finish
  printf 'Recorded %s REPL and overlay\n' "$variant"
done
