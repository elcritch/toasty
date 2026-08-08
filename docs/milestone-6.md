# Milestone 6: Desktop Shell Features

Milestone 6 turns the per-output panel into a complete Merenda desktop shell.
Triad remains the authority for outputs, workspaces, and windows; Toasty owns
presentation state and sends native Triad commands for focus changes.

## Shell Surfaces

The shell creates a background and panel for every connected output. A single
keyboard-exclusive overlay is placed on the output whose panel opened it.
Only one overlay is active at a time:

- **Apps** searches XDG desktop applications, shell commands, and open windows.
- **Overview** groups Triad windows by output and workspace and can focus either.
- **Windows** orders live Triad windows by most recently focused.
- **Bell** displays notifications, unread state, dismiss, and clear-all actions.
- **Quick** exposes volume, default-network status, brightness, and appearance.
- **Power** offers lock, logout, restart, suspend, and poweroff with confirmation.

The pure state transformations live in `shellmodel.nim`. `shellui.nim` owns
Merenda views and navigation state, while `shellapp.nim` only orchestrates the
Triad observer, notification bus, and application lifecycle. This keeps Triad
parsing, platform commands, and UI construction independently testable.

## Applications and Commands

Toasty discovers `[Desktop Entry]` application files in `XDG_DATA_HOME` and
`XDG_DATA_DIRS`. Hidden and `NoDisplay` entries are omitted. The launcher
expands the standard desktop-entry identity fields, removes file/URL fields
when no arguments were supplied, and honors `TOASTY_TERMINAL` for terminal
applications.

An empty query shows the first twelve alphabetized matches. Search ranks exact,
prefix, substring, and fuzzy matches. Pressing `Return` runs the first visible
match; buttons remain available for pointer and keyboard activation.

## Notifications

Toasty owns `org.freedesktop.Notifications` on the session D-Bus and implements
`GetCapabilities`, `Notify`, `CloseNotification`, and
`GetServerInformation`. The supervised session starts a private D-Bus session
when one was not inherited, exports its address to all components, and stops it
during cleanup. A maximum of 100 recent notifications is retained in memory.

From a shell with the session's `DBUS_SESSION_BUS_ADDRESS`, test the daemon with:

```sh
notify-send --expire-time=0 "Milestone 6" "Toasty is online"
```

The active session address is recorded in
`~/.local/state/toasty/session/latest/environment.log`.

## FreeBSD Quick Settings

Platform access is isolated in `systemservices.nim` and can be tested with an
injected command runner. The live adapters are:

| Setting | Probe | Change |
| --- | --- | --- |
| Audio | `/usr/sbin/mixer` | `/usr/sbin/mixer vol=<fraction>` |
| Network | `/sbin/route -n get default` | status and refresh |
| Brightness | `/usr/bin/backlight -q` | `/usr/bin/backlight <percent>` |
| Appearance | Toasty state | switch Merenda dark/light theme |

Controls are disabled when a service is unavailable. Networking is deliberately
read-only: toggling the interface that carries a remote VNC or SSH session is
not a safe desktop default.

## Session Actions

The UI confirms logout, restart, suspend, and poweroff before executing them.
Lock executes immediately. The FreeBSD defaults are:

- lock: `/usr/local/bin/waylock`, then `/usr/local/bin/swaylock`;
- logout: signal the supervised Toasty session;
- restart and poweroff: `/sbin/shutdown`;
- suspend: `/usr/sbin/zzz`.

Set `TOASTY_LOCK_COMMAND`, `TOASTY_LOGOUT_COMMAND`,
`TOASTY_RESTART_COMMAND`, `TOASTY_SUSPEND_COMMAND`, or
`TOASTY_POWEROFF_COMMAND` to replace a default. A missing command disables its
button. Normal FreeBSD authorization still applies.

## Backgrounds, Outputs, and Scale

`TOASTY_WALLPAPER` selects an image for all output backgrounds. Without it,
Toasty renders its built-in branded background. Backgrounds use the Wayland
background layer with no keyboard input; panels use the top layer and reserve
their configured logical height. Overlays use the overlay layer with exclusive
keyboard input while visible.

Every physical width and height received from Triad is divided by the output
scale before a Merenda surface is sized. Output identity is retained while its
current zero-based layer-shell output index is recalculated. Added, removed, or
reordered outputs therefore close stale surfaces and create correctly placed
replacements.

## Keyboard and Accessibility

Opening the launcher focuses its search field. `Return` activates the top
result, and native `Tab`/`Shift-Tab` traversal reaches all actionable controls.
Buttons and search fields have explicit accessible names, identifiers, roles,
and help text. Unavailable platform controls are disabled instead of silently
failing. State is also communicated in text, so connection, workspace,
notification, and availability state do not depend on color alone.

## Validation

The deterministic tests cover desktop-entry parsing and command expansion,
notification replacement/read/expiration behavior, search ranking, recent
windows, per-output logical dimensions, navigation wrapping, and FreeBSD
service parsing through injected runners.

On 2026-08-08, `nim test` and `nim sessionCheck` passed on the FreeBSD host.
The restart check kept River, WayVNC, and the private D-Bus session stable while
Triad and Toasty restarted independently, then verified clean signal shutdown.
A two-head release run created independent background and panel surfaces for
`HEADLESS-1` and `HEADLESS-2` before a clean one-shot shutdown. Through WayVNC
on `127.0.0.1:5905`, the launcher, overview, window switcher, notification
center, quick settings, and session surface were opened by real RFB pointer
input. A `notify-send` request reached Toasty's D-Bus daemon and immediately
appeared as an unread panel notification.
