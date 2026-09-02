import eyg/hub/cache
import gleam/option.{None, Some}
import multiformats/cid/v1
import overlay/helpers
import overlay/web/context
import overlay/web/state
import overlay/web/view

fn example_cid() {
  let assert Ok(#(cid, <<>>)) =
    v1.from_string(
      "bafyreigdmqpykrgxyahdnfmfzmc5j4bkwci6wf6fkdbapq7hfpmg2j3yqy",
    )
  cid
}

pub fn the_default_context_is_not_shown_test() {
  assert view.Default == view.context(helpers.init_default())
}

pub fn a_context_is_shown_while_it_loads_test() {
  let #(state, _actions) = helpers.init(context.Package("foo", Some(1)))
  assert view.Loading("@foo:1") == view.context(state)
}

pub fn a_loaded_context_is_shown_test() {
  let state = helpers.init_default()
  let state =
    state.State(
      ..state,
      context_source: context.Reference(example_cid()),
      context: context.Loaded(context.default()),
    )
  assert view.Loaded("#" <> v1.to_string(example_cid())) == view.context(state)
}

pub fn a_context_that_cannot_be_loaded_is_shown_with_its_reason_test() {
  let #(state, _actions) = helpers.init(context.Package("foo", None))
  let message = state.CacheMessage(cache.PullPackagesCompleted(Ok([])))
  let #(state, _actions) = state.update(state, message)
  assert view.Failed("@foo", "missing reference @foo") == view.context(state)
}

pub fn an_invalid_context_is_shown_with_its_reason_test() {
  let #(state, _actions) = helpers.init(context.from_search("?version=3"))
  assert view.Failed("?version=3", "The version parameter requires a package.")
    == view.context(state)
}
