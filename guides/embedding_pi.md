---
name: Embedding EYG on Raspberry Pi
description: Build a Pi image, check HDMI and serial input, and reuse content-addressed packages from the SD card.
---

# Embedding EYG on Raspberry Pi

[Watch the checked HDMI Pong walkthrough](/glasshouse/pi-pong.mp4).

The [Pi package](../packages/eyg_pi/) boots directly into the Gleam EYG CLI.
Linux supplies drivers; a small native init mounts filesystems, configures the
network and clock, and starts a shell on HDMI and serial. Build tools, emulator
checks and the recorder are Gleam. Interactive programs are EYG.

The checks below ran with Gleam 1.19, Bun 1.3.14, Zig 0.14.1 and QEMU 6.2's
Pi 3B. Physical boards and the included Pi 4 boot assets remain untested.

## Build and boot

Install `gleam`, `bun`, Zig 0.14, QEMU's ARM system emulator, and these Linux
image tools: `xz`, `cpio`, `gzip`, `sfdisk`, `mtools`, `dpkg-deb` and `fdtoverlay`.
On Ubuntu the system packages include `qemu-system-arm`, `cpio`, `mtools`,
`fdisk`, `device-tree-compiler`, `xz-utils` and `dpkg`.

From the repository root:

```sh
cd packages/eyg_pi
gleam run -m eyg_pi/build
gleam run -m eyg_pi/emulate
```

Set `ZIG=/path/to/zig` if needed. The builder pins firmware, kernel and ARM64
glibc, compiles the CLI, and writes `build/sd.img`. Rebuilding creates a new
512 MiB image and replaces its persistent data. The root is an initramfs;
the FAT partition is mounted at `/data`, the shells' working directory.

QEMU opens HDMI in a window and connects serial to the terminal. Type
`!int_multiply(6, 7)` on either console to get `42`. Use Ctrl-A then X in the
host terminal to exit QEMU. `EYG_PI_HEADLESS=1` hides its window.

For a Pi 3, write the image to the intended SD card, attach HDMI, USB keyboard
and wired Ethernet, and power on. `boot/cmdline.txt` requests kernel DHCP;
`config.txt` enables the GPIO UART at 115200 baud. The firmware's
[configuration and overlays](https://www.raspberrypi.com/documentation/computers/config_txt.html)
load the kernel and initramfs. QEMU loads those files directly, applies
`disable-bt` with `fdtoverlay`, and substitutes a USB network adapter for the
board's Ethernet. See QEMU's [Pi device support](https://www.qemu.org/docs/master/system/arm/raspi.html).

## Check input, network and persistence

With the default image and internet access:

```sh
gleam test
eyg script test/pong_test.eyg
gleam run -m eyg_pi/boot_check
gleam run -m eyg_pi/boot_check -- offline
gleam run -m eyg_pi/hdmi_check
```

Use a current repository CLI for the EYG suite; the
[source installation guide](./install_from_source.md) shows how to build it.
The first boot checks serial evaluation, the guessing game's typed `Prompt`
loop, HTTPS `Fetch` and a hub package, then flushes guest writes. The second
starts a fresh guest with external networking disabled and resolves the stored
package. The HDMI check waits for that console
to become ready, types on its USB keyboard, and saves a screenshot with `42` in
`build/screens`. The Pong suite checks movement, wall/paddle collisions, scoring,
serve bounds and quitting. `Prompt` reads a line; `ReadKey(milliseconds)` returns
a named key or `None({})`, with zero providing a poll.

## Package cache and the BEAM

The CLI keeps verified module bodies and ledger replies under
`/data/cache/eyg/hub/<origin-hash>`. CIDs are checked when modules load. Online
processes refresh ledger pages; offline processes can use the last stored
release mapping. Fully [pinned references](./syntax.md#named-packages) keep the
selected release reproducible. Separate hub origins have separate stores.

The two consoles have independent interpreter state and can reuse stored
module bytes. A fresh boot decodes, checks and evaluates those bytes again;
compiled EYG values are not saved. This differs from the BEAM embedding's
session-owned in-memory values and from the
[BEAM code server](https://www.erlang.org/doc/system/code_loading.html), which
loads compiled host modules into the VM. An EYG package is data interpreted by
the existing runtime. Persisted cache files do not install BEAM code.

## Load and record Pong by content ID

The recorder serves the repository's Pong module from a local hub fixture.
Build an overlay whose `etc/eyg/environment` contains:

```text
EYG_ORIGIN=http://10.0.2.2:7207
```

`10.0.2.2` reaches the host from QEMU. Put that file in an overlay directory,
then run from `packages/eyg_pi`:

```sh
EYG_PI_OVERLAY=/absolute/path/to/overlay gleam run -m eyg_pi/build
gleam run -m eyg_pi/record_pong
```

Install `ffmpeg` for this recording. The recorder prints the CID and types:

```eyg
let pong = #baguqeera6zlhch5hmnby2jhvuu34cpr4s32hxcn3yxzvmlxcap77ogavqizq
```

It displays `/t pong.play`, runs `pong.play({})`, steers the left paddle with
USB arrow keys and quits with `q`. The game also accepts `w` and `s`; first to
five points wins. The check confirms a real hub request, reuse by the other
console, the effect signature, moving game frames and return to the shell.
`docs/pong.mp4` records actual QEMU frames; `docs/pong-result.png` shows the end.
