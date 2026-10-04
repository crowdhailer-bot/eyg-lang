#!/bin/bash
# Record setting up EYG in the Ash getting started project, then running scripts from AshAdmin.
#
# Requires Xvfb, openbox, xterm, xdotool, nano, ffmpeg and Chrome.
# Set CHROME to the browser, it defaults to Playwright's Chrome for Testing.
# Run from examples/helpdesk after `mix deps.get` and `mix assets.build`:
#
#     video/record.sh        # writes video/ash-eyg.mp4
#
# Typing is automated, the shell, server and browser are real.
# The standard library is fetched from the live hub when a script refers to it.
set -u
cd "$(dirname "$0")/.."
EXAMPLE=$(pwd)
REPO=$(cd ../.. && pwd)
WORK=$EXAMPLE/_build/video
OUT=$EXAMPLE/video/ash-eyg.mp4
PORT=${PORT:-4100}
CHROME=${CHROME:-$(ls -d ~/.cache/ms-playwright/chromium-*/chrome-linux64/chrome | tail -1)}
# The setup starts from the project as the getting started guide leaves it.
# It is copied to the same depth as this example so `../../packages/ash_eyg` resolves.
START=36eb0848
PROJECT=$REPO/tmp/helpdesk
export DISPLAY=:95
mkdir -p "$WORK"

rm -rf "$PROJECT"
mkdir -p "$PROJECT"
git -C "$REPO" archive "$START" examples/helpdesk | tar -x -C "$PROJECT" --strip-components=2
# Reuse compiled dependencies so Ash is not compiled on camera
cp -r "$EXAMPLE/deps" "$EXAMPLE/_build" "$PROJECT/"
rm -rf "$PROJECT/_build/video"

# The recorded area is 1600x900 below the Chrome for Testing banner.
Xvfb "$DISPLAY" -screen 0 1600x980x24 >/dev/null 2>&1 &
XVFB=$!
sleep 1
openbox >/dev/null 2>&1 &
WM=$!
sleep 1

say() { xdotool type --delay 40 "$1"; }
run() { say "$1"; xdotool key Return; }
click() { xdotool mousemove "$1" "$2" click 1; }
line() { say "$1"; xdotool key Return; }
record() {
  ffmpeg -loglevel error -y -f x11grab -video_size 1600x900 -framerate 15 -i "$DISPLAY.0+0,80" \
    -vsync cfr -r 15 -c:v libx264 -preset ultrafast -crf 26 -pix_fmt yuv420p "$1" </dev/null &
  FFMPEG=$!
}
stop_recording() {
  kill -INT "$FFMPEG"
  wait "$FFMPEG"
}
# Wait for the shell prompt to come back after a command
wait_prompt() {
  for _ in $(seq 1 180); do
    sleep 1
    if [ -e "$WORK/.ready" ]; then rm -f "$WORK/.ready"; return; fi
  done
}
terminal() {
  cat > "$WORK/bashrc" <<EOF
PS1='\[\e[1;32m\]helpdesk\[\e[0m\] $ '
PROMPT_COMMAND='touch $WORK/.ready'
cd $1
clear
EOF
  rm -f "$WORK/.ready"
  xterm -fa DejaVuSansMono -fs 13 -bg '#1e1e2e' -fg '#e0e0e0' -cr '#f5c2e7' -T demo \
    -e bash --rcfile "$WORK/bashrc" >/dev/null 2>&1 &
  TERM_PID=$!
  WIN=$(xdotool search --sync --name '^demo$' | head -1)
  xdotool windowmove "$WIN" 0 80 windowsize "$WIN" 1600 900
  wait_prompt
  xdotool windowactivate --sync "$WIN"
}
edit() { # open a file in nano, find text, move to the end of its line
  run "nano $1"
  sleep 2
  xdotool key ctrl+w; say "$2"; xdotool key Return End
}
save() {
  sleep 2
  xdotool key ctrl+o Return
  sleep 1
  xdotool key ctrl+x
  wait_prompt
}

# Part 1, set up EYG in a shell
terminal "$PROJECT"
record "$WORK/setup.mp4"
sleep 1
run "# The project from the Ash getting started guide"
wait_prompt
run "cat lib/helpdesk/support.ex"
wait_prompt
sleep 2

run "# 1. Add ash_eyg to the dependencies"
wait_prompt
edit mix.exs '{:ash, '
xdotool key Return
say '      {:ash_eyg, path: "../../packages/ash_eyg"},'
save
run "mix deps.get"
wait_prompt
sleep 2
run "clear"
wait_prompt

run "# 2. Expose the domain and its resources"
wait_prompt
edit lib/helpdesk/support.ex 'use Ash.Domain'
say ', extensions: [AshEyg.Domain]'
save
for file in ticket representative; do
  edit "lib/helpdesk/support/$file.ex" 'data_layer: Ash.DataLayer.Ets'
  say ','
  xdotool key Return
  say '    extensions: [AshEyg.Resource]'
  save
done

run "clear; # 3. Every action is now an effect with a type"
wait_prompt
run "mix ash_eyg.effects"
wait_prompt
sleep 6

run "clear; # 4. Run a script, packages it refers to are fetched from the hub"
wait_prompt
run "mix ash_eyg.run -e '@standard.list.map([\"Printer on fire\"], (s) -> { perform SupportTicketOpen({subject: s}) })'"
wait_prompt
sleep 3
run "# Scripts are type checked before they run"
wait_prompt
run "mix ash_eyg.check -e 'perform SupportTicketOpen({subject: 42})'"
wait_prompt
sleep 5
stop_recording
kill "$TERM_PID"

# Part 2, run scripts from AshAdmin in the finished example
# Start the browser off camera, a cold browser takes a while to show its first page.
"$CHROME" --user-data-dir="$WORK/chrome-profile" --no-first-run --no-default-browser-check --disable-gpu \
  --window-position=0,0 --window-size=1600,980 --app="http://127.0.0.1:$PORT/admin" >/dev/null 2>&1 &
BROWSER_PID=$!
xdotool search --sync --name "Ash Admin|127.0.0.1" >/dev/null
sleep 25
terminal "$EXAMPLE"
record "$WORK/admin.mp4"
sleep 1
run "# 5. Run scripts from AshAdmin, the Script resource's run action uses AshEyg.RunScript"
wait_prompt
run "PORT=$PORT mix phx.server"
until curl -s -o /dev/null "http://127.0.0.1:$PORT/admin"; do sleep 1; done
sleep 3

BROWSER=$(xdotool search --name "Ash Admin|127.0.0.1" | head -1)
xdotool windowmove "$BROWSER" 0 0 windowsize "$BROWSER" 1600 980
xdotool windowactivate --sync "$BROWSER" key F5
sleep 4

# Scripting > Script
click 52 272
sleep 1
click 53 308
sleep 2

# The standard library and many effects
click 900 300
line 'let subjects = ["Printer on fire", "Mouse will not click", "Coffee machine is empty"]'
line '@standard.list.map(subjects, (subject) -> {'
line '  perform SupportTicketOpen({subject: subject})'
say '})'
sleep 2
click 924 471
sleep 4
xdotool mousemove 1560 900 click --repeat 3 5
sleep 4

# A type error stops the script before it runs
xdotool mousemove 1560 900 click --repeat 3 4
sleep 1
click 900 300
xdotool key ctrl+a BackSpace
sleep 0.5
say 'perform SupportTicketClose({subject: "Printer on fire"})'
sleep 1.5
click 924 471
sleep 5

# The tickets the script opened
click 52 166
sleep 1
click 53 202
sleep 4
stop_recording

kill "$BROWSER_PID"
xdotool windowactivate --sync "$WIN" key ctrl+c
sleep 1
xdotool key ctrl+c
sleep 2
kill "$TERM_PID" "$WM" "$XVFB"

# Join the parts with a title card
FONT=/usr/share/fonts/truetype/dejavu
ffmpeg -loglevel error -y -f lavfi -i color=c=0x1e1e2e:s=1600x900:d=3:r=15 \
  -vf "drawtext=fontfile=$FONT/DejaVuSans-Bold.ttf:text='Running EYG scripts from AshAdmin':fontcolor=0xe0e0e0:fontsize=56:x=(w-text_w)/2:y=(h-text_h)/2-30,drawtext=fontfile=$FONT/DejaVuSans.ttf:text='with syntax highlighting and the @standard package':fontcolor=0xa0a0b0:fontsize=32:x=(w-text_w)/2:y=(h-text_h)/2+50" \
  -c:v libx264 -preset veryfast -pix_fmt yuv420p "$WORK/title.mp4"
ffmpeg -loglevel error -y -i "$WORK/setup.mp4" -i "$WORK/title.mp4" -i "$WORK/admin.mp4" \
  -filter_complex "[0:v][1:v][2:v]concat=n=3:v=1[v]" -map "[v]" -r 15 \
  -c:v libx264 -preset veryfast -crf 26 -pix_fmt yuv420p -movflags +faststart "$OUT"
rm -rf "$PROJECT"
