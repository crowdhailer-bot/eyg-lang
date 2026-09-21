//// Time each part of replaying a demo, to find what makes steps slow.
//// `gleam run -m jev_playground/profile --runtime bun -- http 40`

import argv
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import jev_playground/agent
import jev_playground/client
import jev_playground/demo
import jev_playground/library
import jev_playground/mock
import jev_playground/packages
import morph/editable as e

pub fn main() {
  let assert [slug, count] = argv.load().arguments
  let assert Ok(count) = int.parse(count)
  let assert Ok(demo) = demo.find(slug)
  let assert Ok(bundle) = packages.bundle()
  let assert Ok(environment) = library.environment(bundle, demo.environment)
  let assert Ok(demo.Prepared(task:, actions:)) =
    demo.prepare(demo, environment)
  let agent = agent.new(task, e.Vacant, environment, demo.config)
  let #(_, totals) =
    list.take(actions, count)
    |> list.index_fold(#(agent, #(0.0, 0.0, 0.0)), fn(acc, action, i) {
      let #(agent, #(o, m, a)) = acc
      let t0 = client.now()
      let offered = agent.options(agent)
      let t1 = client.now()
      let assert Ok(#(evaluation, ms)) =
        mock.answer(offered, agent.candidates(agent, _), action, i)
      let t2 = client.now()
      let assert Ok(agent) = agent.answer(agent, offered, evaluation, ms)
      let t3 = client.now()
      #(agent, #(o +. t1 -. t0, m +. t2 -. t1, a +. t3 -. t2))
    })
  let #(o, m, a) = totals
  let per = fn(x) {
    float.to_string(float.to_precision(x /. int.to_float(count), 1)) <> "ms"
  }
  io.println("options " <> per(o) <> " mock " <> per(m) <> " answer " <> per(a))
}
