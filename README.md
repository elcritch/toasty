# Toasty

Toasty is a FreeBSD-first Wayland desktop built with
[Merenda](https://github.com/elcritch/merenda). River provides the compositor,
Triad manages windows, and Toasty provides the visible desktop shell.

The project currently provides a supervised FreeBSD development session with
these independent processes:

```text
river  <->  triad  <->  toasty
```

Keeping Triad external means the shell can be developed and restarted without
embedding the window manager or compositor.

## Set Up

Install Toasty's Nim dependencies with Atlas:

```sh
atlas install
```

Do not use Nimble for dependency resolution.
If the JSON package index is temporarily unavailable, Atlas can use its full
package-repository fallback:

```sh
atlas --packagesRepo install
```

## Run the Minimal Merenda Window

Build the smallest Merenda window after installing dependencies:

```sh
nim merendaWindow
```

Run it from an active Wayland session:

```sh
nim merendaWindowRun
```

See [Milestone 2 backend audit](docs/milestone-2.md) for the FreeBSD runtime
proof, current capability matrix, and layer-shell integration direction.

## Run the Merenda Panel

Build the solid layer-shell panel with the renderer-specific Siwin Vulkan or
OpenGL layer-surface window selected by FigDraw:

```sh
nim merendaPanel
```

Run it inside an existing Wayland session with:

```sh
nim merendaPanelRun
```

The panel defaults to output index `0`, a height of 48 logical pixels, and no
margin. Override those values with `TOASTY_PANEL_OUTPUT`,
`TOASTY_PANEL_HEIGHT`, and `TOASTY_PANEL_MARGIN`.

## Build Triad on FreeBSD

The `triad` task checks out Triad under `deps/triad`, replays Triad's committed
lockfile with Atlas, applies the temporary FreeBSD `fsnotify` compatibility
patch, and invokes the built-in `atlas-run build` command:

```sh
nim triad
```

For an optimized build:

```sh
nim triadRelease
```

An existing `deps/triad` checkout is reused for compatibility with older
development trees. A clean checkout keeps the external manager outside
Toasty's Atlas graph under `external/triad`. The binaries are therefore
written to one of:

```text
deps/triad/triad
deps/triad/triad_niri
deps/triad/triad_mirror

external/triad/triad
external/triad/triad_niri
external/triad/triad_mirror
```

The task intentionally uses `atlas rep nimble.lock`: Atlas can replay the
upstream lockfile directly, so the dependency revisions match Triad's known
build without invoking Nimble or Nix. Use the built-in `atlas-run build`
command rather than Triad task names such as `buildRelease`, because some
upstream task bodies currently invoke Nimble.

To update the Triad checkout:

```sh
git -C external/triad pull --ff-only
nim triad
```

Use `deps/triad` in that command for an older tree. The task does not update
the checkout automatically, protecting any local Triad work.

## Run the Supervised FreeBSD Session

Build and run the foreground development session:

```sh
nim sessionDev
```

Use optimized Triad and Toasty builds for the release-shaped session:

```sh
nim sessionRelease
```

Supervised sessions use `config.freeform.kdl` by default. It includes Triad's
standard configuration and opens new windows floating. The relevant controls
from the standard configuration are:

- `Super` + left-drag: move
- `Super` + right-drag: resize
- `Super+t`: toggle floating/tiling
- `Super` + middle-click: maximize

Set `TOASTY_TRIAD_CONFIG` to use a different profile, for example:

```sh
TOASTY_TRIAD_CONFIG="$PWD/external/triad/config.default.kdl" nim sessionRelease
```

Windows that were already open must be reopened or toggled individually.
New floating windows currently share Triad's centered default geometry rather
than using cascading or smart placement.

Select a built-in Merenda/NimKit theme with `NIMKIT_THEME`:

```sh
NIMKIT_THEME=nebula nim sessionRelease
```

Available theme names include `darkbsd`, `aqua`, `macos`, `macos-dark`,
`nebula`, `peachy`, and `synthwave83`. The login helper preserves an existing
`NIMKIT_THEME` value, so the same variable can be set by a display-manager or
login environment before running `tools/toasty-session.sh`. When no value is
provided, Toasty uses DarkBSD and its appearance action can toggle to Aqua.

The supervisor starts River, waits for Triad IPC, starts WayVNC on
`127.0.0.1:5905`, and starts Toasty only after the display and remote endpoint
are ready. Triad and Toasty have bounded restart loops; River and WayVNC remain
stable while either component is replaced. Every process has a separate log
below `~/.local/state/toasty/session/`.

Capture the current WayVNC framebuffer as a PNG with the dependency-free
helper:

```sh
tools/wayvnc-screenshot.py /tmp/toasty.png
```

It connects to `127.0.0.1:5905` by default. Use `--host` or `--port` for a
different endpoint; the port also defaults from `TOASTY_VNC_PORT` when set.

Run the live restart and clean-shutdown integration check with:

```sh
nim sessionCheck
```

For an SSH or display-manager login command tied to the checkout, use:

```sh
~/projs/toasty/tools/toasty-session.sh
```

The session refuses to replace an existing graphical session unless
`TOASTY_SESSION_REPLACE=1` is set. See
[Milestone 5 session workflow](docs/milestone-5.md) for launch order,
readiness, restart controls, PID files, FreeBSD packages and services, and
clean-checkout reproduction.

## Run the FreeBSD Session Smoke Test

Start a direct headless River session managed by Triad and exported by WayVNC:

```sh
nim sessionSmoke
```

The task validates Triad's config and River protocols, opens two Foot clients,
exercises focus, workspace, and layout commands, then listens on
`127.0.0.1:5905`. It remains in the foreground until `Ctrl-C`.

The task refuses to disturb an existing River, Sway, or WayVNC process. To
explicitly replace the current remote desktop:

```sh
TOASTY_SESSION_REPLACE=1 nim sessionSmoke
```

For a non-interactive launch check that cleans up immediately:

```sh
TOASTY_SESSION_ONCE=1 nim sessionSmoke
```

To include the Merenda layer-shell panel and validate its Vulkan swapchain and
48-pixel exclusive zone, use the GPU WayVNC path:

```sh
nim panelSmoke
```

`panelSmoke` starts the panel before WayVNC, then launches WayVNC with `--gpu`.
The panel remains interactive through the VNC connection. The one-shot form is:

```sh
TOASTY_SESSION_ONCE=1 nim panelSmoke
```

Timestamped logs and command responses are written below
`~/.local/state/toasty/session-smoke/`; `latest` points to the newest run. Set
`TOASTY_VNC_ADDRESS`, `TOASTY_VNC_PORT`, `TOASTY_SESSION_CLIENT`, or the
`TOASTY_*_BIN` variables to override the defaults.

See [Milestone 1 runtime proof](docs/milestone-1.md) for the recorded FreeBSD
environment, protocol matrix, and smoke-test evidence.

## Inspect Triad Through Toasty IPC

Build the typed native-IPC probe:

```sh
nim triadProbe
```

With Triad running, print its current outputs, workspaces, and windows:

```sh
./examples/triad_probe
```

Observe live layout, state, and window changes with automatic reconnects:

```sh
./examples/triad_probe --watch
```

The socket is discovered from `TRIAD_SOCKET`, then `XDG_RUNTIME_DIR`, with
`/tmp/triad.sock` as the fallback. See
[Milestone 3 typed IPC client](docs/milestone-3.md) for the protocol boundary,
fixture coverage, options, and live Triad-restart proof.

## Run the Toasty Panel

Build the subscription-driven panel and its layer-shell dependencies:

```sh
nim toastyPanel
```

Run it in an existing River/Triad session:

```sh
nim toastyPanelRun
```

The panel creates one layer surface per connected output, using the current
zero-based output index while retaining connector names for panel identity and
labels. It displays Triad workspaces, marks the active and occupied workspace,
shows the focused title, and sends native `focus-workspace` actions when a
workspace is clicked. `NIMKIT_FONT` or `MERENDA_FONT` can override the automatic
FreeBSD Noto Sans/DejaVu Sans fallback.

Run the complete GPU/WayVNC slice check with one output:

```sh
TOASTY_SESSION_ONCE=1 nim sliceSmoke
```

Use two outputs to include the automated secondary-output remove/restore check:

```sh
TOASTY_SESSION_OUTPUTS=2 TOASTY_SESSION_ONCE=1 nim sliceSmoke
```

Force the EGL/OpenGL layer-surface path instead of Vulkan with:

```sh
FIGDRAW_FORCE_OPENGL=1 TOASTY_SESSION_ONCE=1 nim sliceSmoke
```

For an interactive run, omit `TOASTY_SESSION_ONCE`. The local RFB helper can
capture the WayVNC framebuffer and optionally inject a click:

```sh
nim c tools/rfb_smoke.nim
tools/rfb_smoke 127.0.0.1 5905 /tmp/toasty-panel.ppm 192 24
```

See [Milestone 4 first vertical slice](docs/milestone-4.md) for the component
boundary, hotplug behavior, concurrency notes, and recorded FreeBSD proof.

## Use the Desktop Shell

The supervised session starts the complete Toasty shell. Its panel exposes the
application palette, Triad overview, recent-window switcher, notification
center, quick settings, and guarded session actions:

```sh
nim sessionDev
```

Click **Apps** and type to search installed XDG applications, Toasty commands,
and open Triad windows. Press `Return` to run the first match. Native Merenda
focus traversal supports `Tab`, `Shift-Tab`, and `Return` throughout the shell.

To exercise the notification daemon from the same session bus:

```sh
notify-send "Toasty" "The notification center is online"
```

Set a wallpaper before starting the session with
`TOASTY_WALLPAPER=/absolute/path/to/image`. Toasty creates one background and
one panel layer surface per connected output, uses each output's logical size,
and reconciles those surfaces when Triad reports hotplug changes.

On FreeBSD, quick settings use `mixer`, `route`, and `backlight` when available.
Session actions use `waylock` or `swaylock`, the Toasty supervisor, `zzz`, and
`shutdown`; unavailable or unauthorized actions remain disabled. Every command
can be replaced with `TOASTY_LOCK_COMMAND`, `TOASTY_LOGOUT_COMMAND`,
`TOASTY_RESTART_COMMAND`, `TOASTY_SUSPEND_COMMAND`, or
`TOASTY_POWEROFF_COMMAND`.

See [Milestone 6 desktop shell](docs/milestone-6.md) for architecture,
configuration, keyboard behavior, and recorded FreeBSD/WayVNC validation.

## Test

Run the Toasty tests:

```sh
nim test
```

Run one test:

```sh
nim r tests/ttoasty.nim
```

## Project Layout

- `src/`: Toasty shell modules.
- `tests/`: deterministic unit tests.
- `config.nims`: Toasty tests and Atlas-only build and smoke tasks.
- `examples/`: focused integration examples.
- `patches/`: temporary FreeBSD compatibility patches for external components.
- `tools/`: repeatable development-session tooling.
