# eyg tui on the BEAM

`eyg tui` from [gleam_cli](../gleam_cli/), run on the BEAM. The loop, screen and
shell are the same as on JavaScript; `eyg/cli/tui/host` interprets effects in
the same process. Output, prompts, standard input, files, the environment, time
and randomness work. Network requests and writes fail, so hub packages are
unavailable, and other operations stop the evaluation. Overlay needs the
JavaScript runtime.

```sh
gleam run            # or: gleam run <shell file>
gleam test
```

Ctrl+C is the VM's break signal on the BEAM, so quit with `/exit`.
