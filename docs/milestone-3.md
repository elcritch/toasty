# Milestone 3: Typed Triad IPC Client

Milestone 3 adds a typed, view-independent boundary between Toasty and Triad's
native IPC protocol. The implementation was audited against Triad commit
`fb8fb27` and validated in the FreeBSD River session from Milestone 1.

## Socket and Connection Lifecycle

Triad listens on a newline-delimited Unix socket at
`$XDG_RUNTIME_DIR/triad.sock`, falling back to `/tmp/triad.sock` when
`XDG_RUNTIME_DIR` is unset. Triad-managed shell profiles receive an explicit
`TRIAD_SOCKET`; Toasty therefore uses this discovery order:

1. `TRIAD_SOCKET`, when set.
2. `$XDG_RUNTIME_DIR/triad.sock`.
3. `/tmp/triad.sock`.

Each request uses a fresh socket: Toasty connects, writes one protocol-version
1 JSON object and a newline, reads one newline-delimited reply, and closes the
connection. Triad limits request lines to 256 KiB and waits five seconds for a
complete line, so Toasty applies the same limits to replies.

An event subscription has a separate long-lived socket. Toasty sends:

```json
{"triad":{"version":1,"request":"event-stream","events":["layout","state","window"]}}
```

Triad replies with an acknowledgement, an initial layout event, an initial
full-state event, and then incremental events. A read failure closes the old
stream. Toasty waits for the configured reconnect delay, opens the current
socket path again, and consumes the new initial events. Connection callbacks
are emitted only when the connected/disconnected state changes.

Triad refuses to replace a socket that still accepts connections. During a
restart it detects and removes a stale socket before binding the replacement;
the Toasty reconnect loop therefore needs no inode watching or special socket
replacement path.

## Typed Boundary

The IPC code is deliberately separate from Merenda:

- `types.nim` contains the output, workspace, window, snapshot, event, and
  reduced shell-state types.
- `protocol.nim` validates JSON shapes and protocol versions and builds native
  requests.
- `transport.nim` owns Unix socket I/O and exposes callback-injected request
  and stream interfaces.
- `client.nim` provides snapshot, command, and reconnecting subscription APIs.

The client exposes focused wrappers for `focus-workspace`, `focus-window`,
`close-window`, `move-window-to-workspace`, `set-layout`, and `switch-layout`.
Views consume `TriadShellState` and apply typed events; they do not parse JSON
or own sockets.

## Captured Payloads and Tests

The files under `tests/fixtures/` are normalized captures of Triad native
version 1 replies and events from a headless River session. They cover outputs,
workspaces, windows, full state, layout changes, and window changes. Stable
names and process identifiers replace machine-specific values where useful.

`tests/ttriadprotocol.nim` validates the captures, request generation, state
reduction, and rejection of unsupported versions. `tests/ttriadclient.nim`
uses `tests/support/faketriadtransport.nim` to verify snapshots, typed commands,
and continued state reduction across two forced stream disconnections without
network or compositor dependencies.

Run the complete deterministic suite with:

```sh
nim test
```

## Live Probe and Restart Proof

Build the probe:

```sh
nim triadProbe
```

In a Triad session, print the current outputs, workspaces, and windows:

```sh
./examples/triad_probe
```

Watch changes indefinitely, or stop after a bounded number of events:

```sh
./examples/triad_probe --watch
./examples/triad_probe --watch --events:4
```

Use `--socket:PATH` to override discovery and `--reconnect-ms:N` to change the
250 ms reconnect delay.

The live validation on 2026-07-28 used `nim sessionSmoke`, which ran headless
River, two managed Foot clients, and WayVNC with `--gpu`. The probe reported
`HEADLESS-1` at 1280x720, three workspaces, and both windows. After the active
Triad process was stopped, the probe reported a disconnect. A replacement
Triad removed the stale socket, rediscovered the output and both existing
windows, completed initial management, and listened on the same path. The
unchanged probe then reported a connection and received fresh
`layout-state-changed` and `state-changed` events. River, Foot, and WayVNC were
not restarted.

