# Milestone 5: Session and Development Workflow

Milestone 5 turns the one-shot graphics proof into a foreground session with
explicit readiness checks, bounded component restarts, and predictable logs.
`tools/session.sh` remains the process-group owner for the lifetime of the
session.

## Launch and readiness order

The supervisor starts components in this order:

1. River starts with a private `XDG_RUNTIME_DIR`.
2. River launches the bounded Triad supervisor as its external manager.
3. Toasty waits for River's Wayland socket, a successful Triad IPC request,
   and the required River and layer-shell protocol versions.
4. WayVNC starts on the configured loopback endpoint and must accept a TCP
   connection.
5. Toasty starts and must create a renderer-backed panel, connect its Triad
   subscription, and create at least one output surface.

Only then does the supervisor create `ready` and report the session usable.
The default endpoint is `127.0.0.1:5905`, matching the SSH forwarding used by
the development machine.

## Supervision and shutdown

Triad and Toasty may each restart five times after short failures. The default
one-second delay prevents a tight crash loop; a component that runs for at
least 30 seconds resets its failure count. Configure the policy with:

- `TOASTY_SESSION_RESTART_LIMIT`
- `TOASTY_SESSION_RESTART_DELAY`
- `TOASTY_SESSION_RESTART_RESET`

River and WayVNC are session-critical. Their exit stops the complete session.
Triad has a small supervisor launched by River, while Toasty is supervised by
the top-level session process. Killing either component PID exercises the
normal replacement path without changing the River or WayVNC PID:

```sh
kill "$(cat ~/.local/state/toasty/session/latest/triad.pid)"
kill "$(cat ~/.local/state/toasty/session/latest/toasty.pid)"
```

`INT`, `TERM`, and `HUP` sent to the top-level supervisor are forwarded as
normal termination to Toasty, WayVNC, the Triad supervisor, and River in that
order. Shutdown is bounded and never escalates to a force kill:

```sh
kill "$(cat ~/.local/state/toasty/session/latest/session.pid)"
```

An existing River, Sway, or WayVNC session is never replaced implicitly. Set
`TOASTY_SESSION_REPLACE=1` for an intentional handoff. When the existing
session is another supervised Toasty session, its top-level PID receives the
termination signal first.

## Development, release, and login commands

Both session tasks replay and build Triad with Atlas, build the Toasty panel,
and keep the supervisor in the foreground:

```sh
nim sessionDev
nim sessionRelease
```

`sessionDev` uses debug builds. `sessionRelease` builds Triad and Toasty with
release optimization. `tools/toasty-session.sh` is the equivalent login
command for a checkout; it supplies FreeBSD's standard Nim and Atlas binary
paths before running `nim sessionRelease`:

```sh
~/projs/toasty/tools/toasty-session.sh
```

It can be used directly from an SSH login or as the command behind a local
display-manager entry. Keeping the checkout path in that thin command avoids
installing project files into system prefixes before the distribution
milestone.

## Logs and live state

Every run gets a UTC-stamped directory below
`~/.local/state/toasty/session/`; `latest` points at the newest run. Component
output is never combined:

- `river.log`
- `triad.log`
- `wayvnc.log`
- `toasty.log`
- `session.log`
- `wayland-info.log`
- `protocol-check.log`
- `environment.log`

While a session is active, the same directory contains `session.pid`,
`river.pid`, `triad-supervisor.pid`, `triad.pid`, `wayvnc.pid`, `toasty.pid`,
`toasty.ready`, and `ready`. PID and readiness files are removed on shutdown;
the logs remain.

## FreeBSD prerequisites

The validated FreeBSD 15.1 host uses these packages:

```sh
pkg install \
  dbus foot git mesa-dri mesa-libs nim noto-sans pkgconf river seatd \
  vulkan-loader wayland-utils wayvnc
```

Nim is installed under `/usr/local/nim/bin` by the FreeBSD package. Atlas and
its `atlas-run` companion must also be installed and discoverable; Atlas owns
all project dependency resolution. Do not use Nimble to resolve Toasty or
Triad dependencies.

Enable D-Bus for desktop applications:

```sh
sysrc dbus_enable=YES
service dbus start
```

The remote headless backend does not require a running seat daemon. A physical
DRM session does: enable `seatd`, start it, and add the login user to the
`video` group before using `TOASTY_RIVER_BACKENDS=drm`.

WayVNC binds only to loopback by default. Forward it from the workstation:

```sh
ssh -L 5905:127.0.0.1:5905 elcritch@freebsdxx.centaur-barb.ts.net
```

## Reproduction and integration proof

From a clean Toasty checkout:

```sh
atlas install
nim test
TOASTY_SESSION_ONCE=1 nim sessionDev
nim sessionCheck
```

If `packages.nim-lang.org` is unavailable, use
`atlas --packagesRepo install`; the Triad build task selects that same Atlas
fallback automatically when its locked dependency checkouts are absent.

Triad is an external process rather than a Toasty library dependency. Existing
development trees keep using `deps/triad`; a clean checkout provisions it
under ignored `external/triad` so its Atlas graph cannot be mistaken for part
of Toasty's parent `deps/` graph.

The Atlas config may use `link://` name overrides for active FigDraw, Siwin,
and Merenda development checkouts. On the FreeBSD development machine they
resolve to `~/projs/figdraw`, `~/projs/siwin`, and `~/projs/merenda`; generated
`nim.cfg` paths point at those siblings rather than copies under `deps/`.

The live integration check deliberately terminates Triad and Toasty, waits for
new ready PIDs, verifies River and WayVNC kept their original PIDs, then sends
`TERM` to the top-level supervisor and verifies that no component survived.
Its timestamped evidence is stored below
`~/.local/state/toasty/session-check/`.

Run `20260731T041440Z-58207` replaced Triad PID 58256 with 58510 and Toasty
PID 58305 with 58623 while River remained PID 58241 and WayVNC remained PID
58288. The subsequent top-level `TERM` left no component or port 5905 listener
behind.

Clean candidate run `20260731T040949Z-51453` started from an empty Git status,
resolved 34 Atlas packages through the full repository fallback, passed all
17 unit tests, cloned and replayed Triad under `external/triad`, reached the
supervisor ready state, and shut down cleanly. The Git status was still empty
after the run.
