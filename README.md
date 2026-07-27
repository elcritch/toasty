# Toasty

Toasty is a FreeBSD-first Wayland desktop built with
[Merenda](https://github.com/elcritch/merenda). River provides the compositor,
Triad manages windows, and Toasty provides the visible desktop shell.

The project is currently in its bootstrap stage. The first milestone is a
repeatable FreeBSD development session with these independent processes:

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

The binaries are written to:

```text
deps/triad/triad
deps/triad/triad_niri
deps/triad/triad_mirror
```

The task intentionally uses `atlas rep nimble.lock`: Atlas can replay the
upstream lockfile directly, so the dependency revisions match Triad's known
build without invoking Nimble or Nix. Use the built-in `atlas-run build`
command rather than Triad task names such as `buildRelease`, because some
upstream task bodies currently invoke Nimble.

To update the Triad checkout:

```sh
git -C deps/triad pull --ff-only
nim triad
```

The task does not update it automatically, protecting any local Triad work.

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

Timestamped logs and command responses are written below
`~/.local/state/toasty/session-smoke/`; `latest` points to the newest run. Set
`TOASTY_VNC_ADDRESS`, `TOASTY_VNC_PORT`, `TOASTY_SESSION_CLIENT`, or the
`TOASTY_*_BIN` variables to override the defaults.

See [Milestone 1 runtime proof](docs/milestone-1.md) for the recorded FreeBSD
environment, protocol matrix, and smoke-test evidence.

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
- `patches/`: temporary upstream compatibility patches.
- `tools/`: repeatable development-session tooling.
