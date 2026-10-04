# Contributing to EYG

## Running tests

To test all the packages on the BEAM environment.
```sh
# Erlang-target Gleam packages
for pkg in packages/{gleam_analysis,gleam_hub,gleam_ir,gleam_parser,intelligence,overlay_llm,topological,touch_grass,untethered}; do
  ( cd "$pkg" && gleam format --check src test && gleam build --warnings-as-errors && gleam test )
done
```
To test all the packages on the JavaScript environment.
```sh
for pkg in packages/{gleam_analysis,gleam_cli,gleam_compiler,gleam_embed,gleam_hub,gleam_interpreter,gleam_ir,gleam_parser,gleam_x,intelligence,morph,overlay_llm,topological,touch_grass,untethered,website}; do
  ( cd "$pkg" && gleam format --check src test && gleam build --target javascript --warnings-as-errors && gleam test --target javascript --runtime bun )
done
```
Test all the eyg packages.
```sh
eyg script entry.eyg
```

### Embedding examples

Use Gleam 1.18.1 or later for Hashi's Git dependencies in subdirectories.
The browser examples need Bun and a current EYG CLI built from this checkout.
The Ash package and Phoenix example require Elixir 1.17 or later; the helpdesk
requires Elixir 1.20 or later. Use a compatible Erlang/OTP installation and keep
Gleam on `PATH`.

```sh
for pkg in packages/embed_js examples/{todomvc_lustre,hashi,njs}; do
  ( cd "$pkg" && gleam format --check src test && gleam build --target javascript --warnings-as-errors && gleam test --target javascript --runtime bun )
done
( cd packages/embed_js && bun run test )
( cd examples/todomvc_typescript && bun install --frozen-lockfile && bun run build && bun test ./test )
( cd examples/todomvc_lustre && bun install --frozen-lockfile && bun run build )
( cd examples/hashi && eyg script bin/fetch_style.eyg && bun install --frozen-lockfile && bun run build )
( cd examples/erl_counter && gleam build --warnings-as-errors && erl -pa build/dev/erlang/*/ebin -noshell -s erl_counter_test main -s init stop )
for pkg in packages/ash_eyg examples/{phoenix_counters,helpdesk}; do
  ( cd "$pkg" && mix deps.get && mix format --check-formatted && mix test )
done
```

The tests use deterministic host and hub fixtures. The recordings use scripted
model responses. Interactive agents need a configured model provider, and scripts
with uncached package references need access to a hub. For nginx integration,
follow [the njs example](./examples/njs/README.md) to compile and serve the handler.

## Writing EYG packages

All EYG packages are in the `eyg_packages` directory.
A package should expose it's tests as the `tests` field of the entry module.
The entry module will be in `entry.eyg` of the package directory.

The tests for all packages can be run using the repository level `entry.eyg` file.

## Local site development

The infrastructure for the website and hub application is specified as a Docker Compose file in the eyg.run [package](./packages/eyg.run)
This includes a local development setup.

### Create a `.env` file

All configuration is expected to be stored in a `.env` file in the `packages/eyg.run` directory.
The created file needs.

```sh
AUTHORITY=:8001
POSTGRES_HOST=db
POSTGRES_PASSWORD=postgres
SECRET_KEY_BASE=aS3cret
```

Note restarting the docker compose stack will not change the Postgres password value.
The password is taken from the mounted volume, and only uses the env value if the mounted volume is empty.

### Start Docker Compose

```sh
# packages/eyg.run
docker compose -f compose.yaml -f compose.dev.yaml up -d --build
```
Make sure to include the dev file for local development.

You can now visit the website at [localhost:8001](http://localhost:8001)

### Running migrations

Migrations are saved in the [hub package](./packages/hub/)

```sh
# packages/hub
(set -a; source ../eyg.run/.env; POSTGRES_HOST=localhost; set +a; gleam dev migrate)
```
Check the migrations have run by running the hub tests.
```sh
# packages/hub
(set -a; source ../eyg.run/.env; POSTGRES_HOST=localhost; set +a; gleam test)
```

Setting the `POSTGRES_HOST` to localhost is for the migrations to be run outside the docker containers.

## Connect to the database
```sh
# packages/eyg.run
(set -a; source .env; POSTGRES_HOST=localhost; set +a; ./bin/db_tui)
```

## Uploading packages

### Share a module

Upload a module that can be referenced by hash.

Release references must use the fully pinned `@name:version:<module-cid>` form.

```sh
# packages/gleam_cli
EYG_ORIGIN=http://localhost:8001 gleam run -- share ../../eyg_packages/standard/index.eyg.json 
```

### Create a new signatory

```sh
# packages/gleam_cli
EYG_ORIGIN=http://localhost:8001 gleam run -- signatory initial $EYG_ALIAS
```

I normally create an alias `local` for a signatory only registered against the local hub.

### Publish a package

**An administrator must grant a package name to a signatory entity before the hub any published entries.**

Upload a module that can be referenced by hash.

```sh
# packages/gleam_cli
EYG_ORIGIN=http://localhost:8001 gleam run -- publish standard ../../eyg_packages/standard/index.eyg.json 
```
