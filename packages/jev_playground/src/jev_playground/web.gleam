//// Entry point for the playground in the browser.

import jev_playground/app
import jev_playground/view
import lustre

pub fn client() {
  let app = lustre.application(app.init, app.update, view.render)
  let assert Ok(_) = lustre.start(app, "#app", app.location_flags())
  Nil
}
