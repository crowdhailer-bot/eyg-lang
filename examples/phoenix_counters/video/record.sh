#!/bin/bash
# Record typing EYG scripts into the home page of the Phoenix counters example.
#
# Requires Xvfb, openbox, xdotool, ffmpeg, ImageMagick (for --dry screenshots) and Chrome.
# Set CHROME to the browser, it defaults to Playwright's Chrome for Testing.
# Run from examples/phoenix_counters after `mix setup`:
#
#     video/record.sh          # writes video/phoenix-counters.mp4
#     video/record.sh --dry    # screenshots in _build/video/shots, no video
#
# Typing is automated, the page and server are real.
# The standard library is fetched from the live hub when a script refers to it.
set -u
cd "$(dirname "$0")/.."
OUT=$(pwd)/video/phoenix-counters.mp4
WORK=$(pwd)/_build/video
SHOTS=$WORK/shots
DRY=${1:-}
PORT=${PORT:-4100}
CHROME=${CHROME:-$(ls -d ~/.cache/ms-playwright/chromium-*/chrome-linux64/chrome | tail -1)}
export DISPLAY=:96
mkdir -p "$SHOTS"

Xvfb "$DISPLAY" -screen 0 1600x900x24 >/dev/null 2>&1 &
XVFB=$!
sleep 1
openbox >/dev/null 2>&1 &
WM=$!

(PORT=$PORT exec mix phx.server) > "$WORK/server.log" 2>&1 &
SERVER=$!
until curl -s -o /dev/null "http://127.0.0.1:$PORT"; do sleep 1; done

shot() { import -window root "$SHOTS/$1.png"; }
say() { xdotool type --delay 45 "$1"; }
newline() { xdotool key shift+Return; }

"$CHROME" --user-data-dir="$WORK/chrome-profile" --no-first-run --no-default-browser-check --disable-gpu \
  --force-device-scale-factor=1.25 --window-position=0,0 --window-size=1600,900 \
  --app="http://127.0.0.1:$PORT" >/dev/null 2>&1 &
BROWSER=$!
# A cold browser profile can take a while to show its first page
xdotool search --sync --name "PhoenixCounters" >/dev/null
sleep 10
# Focus the script box
xdotool mousemove 800 400 click 1 mousemove 1560 860

if [ "$DRY" != "--dry" ]; then
  # Skip the title bar and the Chrome for Testing banner
  ffmpeg -loglevel error -y -f x11grab -video_size 1600x808 -framerate 15 -i "$DISPLAY.0+0,92" \
    -vsync cfr -r 15 -c:v libx264 -preset ultrafast -crf 26 -pix_fmt yuv420p \
    -movflags +faststart "$OUT" </dev/null &
  FFMPEG=$!
fi
sleep 2

# A single effect
say 'perform StartCounter("apples")'
sleep 1.5
shot 01-typed
xdotool key Return
sleep 3
shot 02-single

# Type errors are shown as the script is typed
say 'perform StartCounter(1)'
sleep 3
shot 03-error
xdotool key ctrl+a BackSpace
sleep 1

# Several effects
say 'let _ = perform StartCounter("pears")'
newline
say 'let _ = perform SetTickRate({name: "pears", seconds: 1})'
newline
say 'perform GetValue("pears")'
sleep 1.5
xdotool key Return
sleep 4
shot 04-multiple

# The standard library, fetched from the hub the first time a script refers to it
say 'let names = ["plums", "figs", "limes", "kiwis"]'
newline
say '@standard.list.map(names, (name) -> {'
newline
say '  let _ = perform StartCounter(name)'
newline
say '  perform SetTickRate({name: name, seconds: 2})'
newline
say '})'
sleep 3
shot 05-standard-typed
xdotool key Return
sleep 8
shot 06-standard

if [ "$DRY" != "--dry" ]; then
  kill -INT "$FFMPEG"
  wait "$FFMPEG"
fi
kill "$BROWSER" "$SERVER"
sleep 1
kill "$WM" "$XVFB"
