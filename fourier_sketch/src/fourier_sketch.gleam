import app
import lustre

pub fn main() -> Nil {
  let boot = lustre.application(app.init, app.update, app.view)
  let _ = lustre.start(boot, "#app", Nil)
  Nil
}
