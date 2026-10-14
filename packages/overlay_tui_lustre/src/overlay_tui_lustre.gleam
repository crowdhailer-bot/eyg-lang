import overlay_tui_core
import terminal_lustre/mount

pub fn main() {
  overlay_tui_core.launch(mount.mount)
}
