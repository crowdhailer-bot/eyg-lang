# Contributing to EYG

## Running tests

The [CI workflow](.github/workflows/test.yml) lists every package checked on each runtime.
EYG package tests use a CLI built from this checkout, run `gleam run -m compile` in packages/gleam_cli to build it locally.

To test the core packages on the BEAM environment.
```sh
# Erlang-target Gleam packages
for pkg in packages/{gleam_analysis,gleam_hub,gleam_ir,gleam_parser,gleam_sha256,intelligence,overlay_llm,topological,touch_grass,untethered}; do
  ( cd "$pkg" && gleam format --check src test && gleam build --warnings-as-errors && gleam test )
done
```
To test the core packages on the JavaScript environment.
Build the standalone native API before its tests import the bundle:
```sh
( cd packages/embed_js && bun install && gleam run -m build )
```
```sh
for pkg in packages/{example_tools,embed_js,glasshouse,gleam_analysis,gleam_cli,gleam_compiler,gleam_compiled_runtime,gleam_embed,gleam_hub,gleam_interpreter,gleam_ir,gleam_parser,gleam_sha256,gleam_x,intelligence,loam,morph,otel,overlay_eval,overlay_llm,overlay_web,plinthx,topological,touch_grass,untethered,website}; do
  ( cd "$pkg" && gleam format --check src test && gleam build --target javascript --warnings-as-errors && gleam test --target javascript --runtime bun )
done
```
Test all the eyg packages.
```sh
eyg script entry.eyg
```

Browser recordings and real Jaeger/Langfuse checks are described in the
[trajectory guide](./guides/trajectories.md). Their workflows and model fixture
are Gleam modules in `packages/tracing`.

The [terminal shell guide](./guides/tui_shell.md) covers `eyg tui`. Its checked
recordings are orchestrated by `tracing/terminal_demo`.

The [Pi guide](./guides/embedding_pi.md) builds and boots the image with Gleam
modules in `packages/eyg_pi`. Its `boot_check` checks online then offline cache
reuse, `hdmi_check` checks USB input, and `record_pong` checks and records a real
CID-loaded game. Run its Gleam tests and `eyg script test/pong_test.eyg` there.

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
(set -a; source ../eyg.run/.env; POSTGRES_HOST=localhost; set +a; gleam run -m hub_dev -- migrate)
```
Check the migrations have run by running the hub tests.
```sh
# packages/hub
(set -a; source ../eyg.run/.env; POSTGRES_HOST=localhost; set +a; gleam test)
```

Setting the `POSTGRES_HOST` to localhost is for the migrations to be run outside the docker containers.
Use `POSTGRES_PORT` when the database is exposed on a port other than 5432.
The hub HTTP port is set with `PORT` and defaults to 8080.

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
