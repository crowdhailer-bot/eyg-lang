# trafiklab

An example usecase context. Once the package has been published, start an
overlay session with it and ask when the next bus leaves.

```
https://eyg.run/overlay?package=trafiklab
```

The module is a record with a `readme`, which is what makes it a context. The
readme is the agent's instructions, and the module is in scope, as `context`,
for every program the agent writes.

## Public API

| Helper                        | What it does                                                    |
| ----------------------------- | --------------------------------------------------------------- |
| `buses({site, forecast})`     | Buses leaving a stop in the next `forecast` minutes.             |
| `departures({site, forecast})`| The same for every mode, not just buses.                         |
| `sites({name})`               | `Result(List({id, name}), String)`, find a stop id by name.      |
| `moa_martinsons_torg`         | The site id `1251`.                                              |
| `eyvind_johnsons_gata`        | The site id `1254`.                                              |

A departure is `{destination, direction, display, scheduled, expected, line,
transport}`. `display` is the human reading, such as `"Nu"`, `"3 min"`, or an
absolute clock time such as `"19:22"`.

## The API

[SL Transport](https://transport.integration.sl.se), covering Stockholm. It
needs no API key, which is why it makes a good demo: nothing is set up before
the session starts.

These functions were ported from the Gleam
`midas/sdk/trafiklab/realtidsinformation_4`, which called `api.sl.se`. That host
no longer resolves, the SL Transport API replaced it. The site ids carried over,
`1251` is still Moa Martinsons torg.

`sites` fetches every stop in the network, over a megabyte, so prefer a known
id.

## Tests

```sh
eyg script eyg_packages/trafiklab/entry.eyg
```

Every function is covered with `Fetch` answered by a handler, so the tests never
touch the network.
