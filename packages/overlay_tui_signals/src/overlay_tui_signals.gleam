import overlay_tui_core
import signals/view

pub fn main() {
  overlay_tui_core.launch(view.mount)
}
