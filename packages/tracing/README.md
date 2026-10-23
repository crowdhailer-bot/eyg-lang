# Checks and recordings

Gleam programs that drive EYG tools as a person would and keep evidence of
what happened.

- `gleam run -m tracing/tui_check`: use `eyg tui` in tmux, typing keys and
  waiting at each check for text on the screen. Build packages/gleam_cli first.
  Packages come from a local hub on port 7207. Each checked screen and an
  asciinema cast are in `recordings/tui`.
