//// The browser as an environment: everything `touch_grass/harness/browser`
//// describes, carried out by `pal`.
////
//// This is the environment overlay runs in when it is a page of its own rather
//// than embedded in something. It keeps no state of its own, so its host is
//// `Nil`.

import eyg/interpreter/simple_debug
import eyg/interpreter/state as istate
import eyg/interpreter/value as v
import ogre/origin
import overlay/web/environment.{
  type Environment, type Handling, Environment, Stopped, Unknown, Working,
}
import pal/platform/browser
import touch_grass/harness/browser as harness
import touch_grass/http

pub fn environment(origin: origin.Origin) -> Environment(Nil) {
  Environment(
    host: Nil,
    handler: handle,
    briefing: briefing(origin),
    effects: harness.types(harness.effects()),
    scope: [],
  )
}

pub fn handle(
  host: Nil,
  label: String,
  lift: istate.Value(environment.Meta),
) -> #(Nil, Handling) {
  #(host, case browser.cast(label, lift) {
    Ok(effect) ->
      case browser.extrinsic(effect) {
        browser.Abort(reason) -> Stopped(reason)
        browser.Work(effect) -> Working(effect)
        browser.Spotless(..) ->
          Stopped("Spotless integration not supported in harness")
      }
    Error(reason) -> Unknown(reason)
  })
}

fn briefing(origin: origin.Origin) -> String {
  let scheme = http.scheme_to_eyg(origin.scheme)
  let host = v.String(origin.host)
  let port = v.option(origin.port, v.Integer)

  "To fetch a guide run the following script.
ALWAYS fetch the EYG syntax guide before writing scripts

```eyg
let request = {
  method: GET({}),
  scheme: " <> simple_debug.inspect(scheme) <> ",
  host: " <> simple_debug.inspect(host) <> ",
  port: " <> simple_debug.inspect(port) <> ",
  path: \"/guides/eyg-syntax-guide.md\",
  query: None({}),
  headers: [],
  body: !string_to_binary(\"\")
}
match perform Fetch(request) {
  Ok({body}) -> {
    match !string_from_binary(body) {
      Ok(text) -> { text }
      Error(_) -> { \"Not a utf-8 response.\" }
    }
  }
  Error(reason) -> { !string_append(\"fetch guide \", reason) }
}
```

Other guides are
- /guides/builtins-reference.md
- /guides/http-fetch.md

Use the service effects, such as DNSimple, to call service API's these do not require the scheme, host or port to be set.
They do not require an API token this will be added by the platform."
}
