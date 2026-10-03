#!/bin/bash
# Record joining the cluster, running scripts and inspecting counters in Observer.
#
# Requires Xvfb, openbox, xterm, xdotool, ffmpeg and ImageMagick (for --dry screenshots).
# Run from examples/erl_counter:
#
#     video/record_observer.sh            # writes video/erl-counter-observer.mp4
#     video/record_observer.sh --dry      # screenshots in build/observer-shots, no video
#
# Typing is automated, everything shown is a real Erlang session.
# The standard library is fetched from the live hub when the script needs it.
set -u
cd "$(dirname "$0")/.."
EXAMPLE=$(pwd)
OUT=$EXAMPLE/video/erl-counter-observer.mp4
SHOTS=$EXAMPLE/build/observer-shots
DRY=${1:-}
HOST=$(hostname -s)
NODE=eyg_counters_observer
SHELL_NODE=eyg_observer_shell
export DISPLAY=:97

gleam build --warnings-as-errors || exit 1
mkdir -p "$SHOTS"

Xvfb "$DISPLAY" -screen 0 1600x900x24 >/dev/null 2>&1 &
XVFB=$!
sleep 1
openbox >/dev/null 2>&1 &
WM=$!
sleep 1

XT=(xterm -fa DejaVuSansMono -fs 11 -bg '#1e1e2e' -fg '#e0e0e0' -cr '#f5c2e7')
shot() { import -window root "$SHOTS/$1.png"; }
win() { xdotool search --sync --name "^$1\$" | head -1; }
say() { xdotool windowactivate --sync "$1" type --delay 35 "$2"; }
enter() { xdotool windowactivate --sync "$1" key Return; }
line() { say "$1" "$2"; enter "$1"; }

if [ "$DRY" != "--dry" ]; then
  ffmpeg -loglevel error -y -f x11grab -video_size 1600x900 -framerate 15 -i "$DISPLAY" \
    -vsync cfr -r 15 -c:v libx264 -preset ultrafast -crf 26 -pix_fmt yuv420p \
    -movflags +faststart "$OUT" </dev/null &
  FFMPEG=$!
  sleep 1
fi

# Terminal 1 starts the application on a named node
"${XT[@]}" -T node -geometry 82x10+0+0 -e bash --norc >/dev/null 2>&1 &
NODE_TERM=$(win node)
xdotool windowmove "$NODE_TERM" 0 0
sleep 1
line "$NODE_TERM" "erl -sname $NODE -pa build/dev/erlang/*/ebin -eval '{ok, _} = application:ensure_all_started(erl_counter).' 2>/dev/null"
sleep 6

# Terminal 2 joins the cluster with a remote shell
"${XT[@]}" -T dev -geometry 82x35+0+210 -e bash --norc >/dev/null 2>&1 &
DEV=$(win dev)
xdotool windowmove "$DEV" 0 210
sleep 1
line "$DEV" "erl -sname $SHELL_NODE -remsh $NODE@$HOST"
sleep 4
line "$DEV" "node()."
sleep 1
# The session process owns the package cache, the shell only sees results
line "$DEV" "{ok, S} = counters_session:start_link()."
sleep 1
line "$DEV" 'Show = fun({ok, T}) when is_binary(T) -> io:format("~ts~n", [T]); ({ok, V}) -> io:format("~ts~n", [eyg@interpreter@simple_debug:inspect(V)]); ({error, E}) -> io:format("~ts~n", [E]) end.'
sleep 1
xdotool windowactivate --sync "$DEV" key ctrl+l
sleep 1

line "$DEV" "observer:start()."
OBS=$(win "$NODE@$HOST")
sleep 3
xdotool windowmove "$OBS" 750 0 windowsize "$OBS" 850 900
sleep 1
# Applications tab
xdotool mousemove 1232 63 click 1
sleep 2
shot 01-observer

# A single effect
line "$DEV" 'Show(counters_session:run(S, "perform StartCounter(\"apples\")")).'
sleep 3
shot 02-single

# Type errors are found before anything runs
line "$DEV" 'Show(counters_session:check(S, "perform StartCounter(1)")).'
sleep 3
shot 03-check

# Several effects
line "$DEV" 'Show(counters_session:run(S, "'
line "$DEV" '  let _ = perform StartCounter(\"pears\")'
line "$DEV" '  let _ = perform SetTickRate({name: \"pears\", seconds: 1})'
line "$DEV" '  perform GetValue(\"pears\")'
line "$DEV" '")).'
sleep 3
shot 04-multiple

# Inspect the shape of a counter
xdotool mousemove 1256 113 click --repeat 2 --delay 80 1
sleep 3
PROC=$(xdotool search --name "$NODE@$HOST:<" | head -1)
xdotool windowmove "$PROC" 750 0 windowsize "$PROC" 850 900
sleep 1
xdotool mousemove 1252 63 click 1
sleep 5
shot 05-state
xdotool windowclose "$PROC"
sleep 2

# The standard library, fetched from the hub when the script refers to it
xdotool windowactivate --sync "$DEV" key ctrl+l
line "$DEV" 'Show(counters_session:run(S, "'
line "$DEV" '  let names = [\"plums\", \"figs\", \"limes\", \"kiwis\"]'
line "$DEV" '  @standard.list.map(names, (name) -> {'
line "$DEV" '    let _ = perform StartCounter(name)'
line "$DEV" '    perform SetTickRate({name: name, seconds: 2})'
line "$DEV" '  })'
line "$DEV" '")).'
sleep 8
shot 06-standard

line "$DEV" 'Show(counters_session:run(S, "perform GetValue(\"pears\")")).'
sleep 5
shot 07-value

if [ "$DRY" != "--dry" ]; then
  kill -INT "$FFMPEG"
  wait "$FFMPEG"
fi

# Stop only the nodes started for this recording
line "$DEV" "rpc:call('$NODE@$HOST', init, stop, [])."
sleep 3
for w in $(xdotool search --name '^(node|dev)$'); do xdotool windowclose "$w"; done
sleep 1
kill "$WM" "$XVFB"
