# Milestone 4: First Vertical Slice

Milestone 4 turns the typed Triad client and Merenda layer-shell backend into a
usable panel. The executable is `examples/toasty_panel.nim`; `nim toastyPanel`
builds it with the linked Siwin, FigDraw, and Merenda layer-shell APIs.

## Component boundary

`src/toasty/panelmodel.nim` is the backend-independent projection from
`TriadShellState` to one `PanelViewModel` per connected output. It assigns each
workspace to its output, preserves configured names, exposes active, urgent,
and occupied state, and selects the focused title with app-ID and `Desktop`
fallbacks.

`src/toasty/shellapp.nim` owns the Merenda views. It reconciles layer-surface
hosts by Triad output ID, rebuilds workspace controls after state changes, and
sends `focus-workspace` through the typed client. Connector names remain the
state and display identity, while the renderer-specific native layer surface
is selected with the output's current zero-based index.

The Triad observer runs on one Sigils worker. It blocks on Triad's native event
stream and transfers owned `TriadEvent` and `TriadSnapshot` values through a
synchronized channel. A payload-free signal wakes the Merenda application
thread, where state reduction and view reconciliation occur. There are no
repeated state queries or timer-driven refreshes. The bounded socket wait only
allows clean shutdown and reconnect detection.

The event-stream transport waits for socket readability before consuming an
available chunk. This matters for large state events: applying a timeout to a
fixed-size `recv` consumed partial JSON before raising, which the live slice
exposed and the new buffered transport avoids.

## Output and restart behavior

State events can briefly identify a returning connector as `river-<id>` before
Triad restores its `wl_output` name. The reducer retains known output metadata
across removal and rewrites matching workspace and window references, so the
panel never exposes that transient identity. Removing an output closes its
host; restoring it creates a new host after connected outputs have been
reindexed.

Every successful subscription refreshes the full snapshot. Toasty therefore
reconstructs current state after Triad's socket is replaced instead of relying
on events that may have occurred while disconnected. Toasty and Triad were
both stopped and restarted independently while the River and WayVNC PIDs stayed
unchanged. Restarting the whole River smoke session recreates the same guarded
VNC endpoint; bounded production supervision remains Milestone 5 work.

## Appearance and shell ownership

The slice uses Merenda's DarkBSD appearance plus a dark panel background. It
selects `/usr/local/share/fonts/noto/NotoSans-Regular.ttf`, then DejaVu Sans,
unless `NIMKIT_FONT` or `MERENDA_FONT` is already set. Active workspaces receive
an explicit `>` marker, occupied workspaces `*`, and urgent workspaces `!`, so
the essential state remains legible independently of button-theme details.

Toasty sends `hide-hotkey-overlay` on every Triad connection. The panel uses
the top layer rather than the overlay layer, reserves 48 logical pixels, and
does not request keyboard focus.

## Deterministic coverage

`nim test` covers:

- projection to multiple outputs, disconnected-output compaction, workspace
  naming/state, and focused-title fallbacks;
- typed and raw event observers, reconnect transitions, overlay and workspace
  command generation;
- connector-name retention across a remove/re-add snapshot; and
- the existing captured Triad parser and reducer fixtures.

## FreeBSD runtime proof

The final two-output one-shot proof is:

```sh
TOASTY_SESSION_OUTPUTS=2 TOASTY_SESSION_ONCE=1 nim sliceSmoke
```

Run `20260729T020411Z` used FreeBSD 15.1, River 0.4.5, WayVNC 0.10.1 with
`--gpu`, the AMD Radeon 780M Vulkan device, and two 1280x720 headless outputs.
It created 1280x48 Vulkan layer surfaces for `HEADLESS-2` and `HEADLESS-1`,
observed focused-title and workspace 1/2 changes, hid the Triad hotkey overlay,
and reserved the expected 48-pixel exclusive zone. The automated power cycle
removed and recreated the `HEADLESS-1` panel while Toasty, River, and WayVNC
remained alive. That proof used the earlier connector-name-targeted backend.

The renderer-specific output-index path was revalidated in two one-shot runs
on 2026-07-30 MDT. Run `20260731T022624Z` created independent 1280x48 Vulkan
mailbox swapchains for `HEADLESS-2` and `HEADLESS-1` through
`VK_KHR_wayland_surface`; the secondary output was removed and recreated at
index 1 without panel or IPC errors. Run `20260731T022826Z` forced FigDraw's
OpenGL path, created an AMD Radeon EGL/OpenGL ES 3.2 context, reserved the same
48-pixel exclusive zone, and passed the complete one-output smoke sequence.

The final interactive proof is under run `20260729T020523Z`. The RFB 3.8 helper
captured the 1280x720 WayVNC framebuffer, visibly showing the output label,
`> * 1`, workspace buttons 2 and 3, the focused Foot title, and the connection
indicator. A press/release at `(192, 24)` hit workspace 2. Toasty logged
`workspace-click: output=HEADLESS-1 workspace=2`, Triad reported workspace 2
active, and the subscription changed the panel's active marker without polling.

Timestamped command responses, component logs, screenshots, and the click proof
are stored below `~/.local/state/toasty/session-smoke/`; `latest` points at the
newest run.
