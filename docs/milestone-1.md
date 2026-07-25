# Milestone 1: River and Triad Runtime Proof

This record describes the FreeBSD smoke session validated on 2026-07-24
(2026-07-25 UTC).

## Initial session audit

The pre-existing WayVNC-visible desktop was owned by Sway, not River:

```text
FreeBSD 15.1-RELEASE-p1
Sway 1.12
WayVNC 0.10.1
WAYLAND_DISPLAY=wayland-1
XDG_RUNTIME_DIR=/home/elcritch/.local/wayland-runtime
WLR_BACKENDS=headless
WLR_RENDERER=pixman
output=HEADLESS-1 (1280x720)
seat=default (wl_seat v9)
WayVNC=127.0.0.1:5905
```

`procstat` and Unix-socket ownership showed that Sway PID 11330 owned
`wayland-1`, while WayVNC PID 11493 was its client.

## Session design

The development machine is remote-only and its compositor already uses the
headless backend. The milestone session therefore replaces Sway instead of
nesting River inside it. This removes an extra compositor from the input and
rendering paths while remaining safe for the physical machine: River uses one
1280x720 headless output, Pixman rendering, a private temporary
`XDG_RUNTIME_DIR`, and WayVNC bound only to loopback.

The launcher refuses to replace an existing graphical session unless
`TOASTY_SESSION_REPLACE=1` is present. It sends normal termination signals and
refuses to force-kill a process that does not stop.

## Validated versions and protocols

The successful run used:

```text
River 0.4.5 -xwayland
WayVNC 0.10.1
Triad fb8fb27ec294e0fe2361375de0b2fa8c08be0ca9
```

Triad's required protocol matrix passed:

| Protocol | River | Triad minimum |
| --- | ---: | ---: |
| `river_window_manager_v1` | 4 | 4 |
| `river_xkb_bindings_v1` | 3 | 2 |
| `wl_compositor` | 6 | 1 |
| `wl_shm` | 2 | 1 |

The installed River advertises version 1 of `river_xkb_config_v1`,
`river_input_manager_v1`, and `river_libinput_config_v1`; this Triad checkout
prefers version 2. Triad classifies all three as optional and reports
`required=ok optionalWarnings=3`. Core window management, bindings, output
management, overlay surfaces, pointer gestures, idle inhibition, cursor
shapes, and single-pixel surfaces are available. River protocol v4 does not
provide Triad's optional capture-session accounting, so the reported
`capture_sessions` capability is false.

## Repeatable command

When no compositor is running:

```sh
nim sessionSmoke
```

To replace the current Sway/River and WayVNC processes:

```sh
TOASTY_SESSION_REPLACE=1 nim sessionSmoke
```

The command performs these checks before remaining in the foreground:

1. Validate `deps/triad/config.default.kdl`.
2. Start River with `WLR_BACKENDS=headless`, `WLR_RENDERER=pixman`, and one
   headless output.
3. Start `deps/triad/triad` as River's external manager.
4. Capture `wayland-info` and enforce Triad's required protocol versions.
5. Launch two Foot clients with app ID `toasty-smoke` and wait until Triad
   reports both.
6. Verify `focus-prev` changes focus and `focus-next` restores it.
7. Activate workspace 2, return to workspace 1, and verify the state.
8. Select and verify the grid and tile layouts.
9. Start WayVNC on `127.0.0.1:5905` and verify the listener.

Use `TOASTY_SESSION_ONCE=1 nim sessionSmoke` for the same automated checks with
immediate cleanup.

## Evidence

Each run writes a timestamped directory under:

```text
~/.local/state/toasty/session-smoke/
```

The `latest` symlink identifies the newest run. Important files are:

- `environment.log`: versions, display, runtime directory, backend, renderer,
  seat, and VNC endpoint.
- `protocol-check.log`: enforced required-protocol versions.
- `wayland-info.log`: complete advertised Wayland registry.
- `commands.log`: Triad IPC requests and state responses.
- `triad.log`: manager startup, protocol diagnostics, output/seat discovery,
  and managed-window discovery.
- `river-triad.log`: River and wlroots diagnostics.
- `wayvnc.log`: WayVNC diagnostics.

The automated proof run at `20260725T003347Z` passed. It reported one
`HEADLESS-1` output, two managed `toasty-smoke` windows, a focus round trip,
workspace 2 active during the workspace check, and the grid then tile layouts
active on workspace 1.

The persistent run at `20260725T003504Z` completed the remote interaction
proof. An RFB 3.8 client received the 1280x720, 32-bit WayVNC framebuffer,
injected text into the focused Foot client, and received a changed framebuffer
hash. A pointer click at `(320, 360)` then changed Triad's focused window from
ID `4278190085` to `4278190084`. This confirms both framebuffer delivery and
WayVNC keyboard/pointer input through River into Triad-managed clients.
