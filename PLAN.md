# Toasty Plan

Build a FreeBSD-first Wayland desktop where River is the compositor, Triad is
the external window manager, and Toasty is a Merenda-based desktop shell.

## Constraints

- Atlas manages Nim dependencies; do not use Nimble or Nix.
- River, Triad, and Toasty remain separate processes.
- FreeBSD is the primary development and runtime target.
- WayVNC is the remote visual test path.
- Merenda owns visible shell UI; Triad owns window-management policy.
- Prefer upstream fixes or small temporary patches over permanent forks.

## Completed Foundation

- [x] Rename the Nim package and root module to Toasty.
- [x] Choose the River + Triad + Toasty process architecture.
- [x] Establish SSH access to the FreeBSD development machine.
- [x] Mirror the Toasty checkout to `~/projs/toasty`.
- [x] Build Triad with Atlas instead of Nimble or Nix.
- [x] Replay Triad's committed dependency revisions with
      `atlas rep nimble.lock`.
- [x] Add the temporary FreeBSD `fsnotify` compatibility patch.
- [x] Add `nim triad` and `nim triadRelease` build tasks.
- [x] Build all three Triad binaries on FreeBSD.
- [x] Validate Triad's default configuration on FreeBSD.
- [x] Run Toasty's tests locally and on FreeBSD.
- [x] Commit the Atlas build workflow as `e699205`.

## Milestone 1: River and Triad Runtime Proof

Prove that the compositor and manager work together in a session visible over
WayVNC before building shell UI.

- [ ] Record the installed River and WayVNC versions.
- [ ] Record the active `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`, seat, and backend.
- [ ] Confirm which compositor currently owns the WayVNC-visible session.
- [ ] Verify that River exposes every protocol required by the current Triad
      checkout.
- [ ] Decide whether the development session should be nested or replace the
      current compositor.
- [ ] Start an isolated River session without disturbing the existing remote
      desktop.
- [ ] Start `deps/triad/triad` as River's external manager.
- [ ] Launch a simple Wayland client and confirm Triad manages it.
- [ ] Exercise focus, workspace, and layout commands through `triad msg`.
- [ ] Confirm the complete session is visible and interactive through WayVNC.
- [ ] Capture logs and document the exact environment and launch command.
- [ ] Add a repeatable `nim session` or `nim sessionSmoke` task.

Exit criteria:

- [ ] River, Triad, a test client, and WayVNC work together for a complete
      interactive smoke test.
- [ ] The smoke session can be started again from one documented command.

## Milestone 2: Merenda Wayland Shell Surface

Resolve the largest UI risk early: desktop panels and overlays need layer-shell
semantics rather than ordinary application windows.

- [ ] Add Merenda to `toasty.nimble` through Atlas.
- [ ] Resolve and pin a reproducible Merenda dependency graph.
- [ ] Compile and run the smallest Merenda window on FreeBSD.
- [ ] Confirm Merenda's current Siwin backend behavior under River.
- [ ] Audit support for transparency, undecorated windows, output selection,
      scaling, keyboard interactivity, and pointer input.
- [ ] Audit support for `wlr-layer-shell`, anchors, margins, exclusive zones,
      and per-output surfaces.
- [ ] Build a minimal layer-shell surface with a solid Merenda-rendered panel.
- [ ] Decide whether layer-shell support belongs in Siwin, Merenda, or a small
      Toasty Wayland host adapter.
- [ ] Add a focused test or example for the chosen surface integration.

Exit criteria:

- [ ] A Merenda-rendered panel surface appears on a chosen River output.
- [ ] The panel reserves space and receives pointer input correctly.
- [ ] The integration direction is documented before broader UI work starts.

## Milestone 3: Typed Triad IPC Client

Give Toasty a narrow, testable boundary to the external window manager.

- [ ] Document Triad's native socket discovery and connection lifecycle.
- [ ] Capture representative workspace, window, output, and event payloads.
- [ ] Define Toasty types for the shell state actually needed by the UI.
- [ ] Implement snapshot requests and event subscriptions.
- [ ] Implement focus, workspace, layout, and window commands.
- [ ] Add reconnect behavior for Triad restarts and socket replacement.
- [ ] Keep parsing and transport separate from Merenda views.
- [ ] Add deterministic parser tests using captured payloads.
- [ ] Add a fake transport for shell view-model tests.

Exit criteria:

- [ ] A command-line Toasty probe prints live outputs, workspaces, and windows.
- [ ] The probe observes changes and survives a Triad restart.

## Milestone 4: First Vertical Slice

Build one useful shell component end to end before expanding the desktop.

- [ ] Show one panel per output.
- [ ] Display workspace names and active state from Triad IPC.
- [ ] Display the focused application's title.
- [ ] Focus a workspace when its panel item is clicked.
- [ ] Update the panel from subscriptions without polling.
- [ ] Handle output add/remove events.
- [ ] Apply a basic Merenda theme and FreeBSD-appropriate font fallback.
- [ ] Disable or avoid overlapping Triad shell overlays.
- [ ] Verify the slice visually and interactively through WayVNC.

Exit criteria:

- [ ] The panel is usable for workspace navigation during a real River session.
- [ ] River, Triad, or Toasty can restart independently without losing the
      entire remote session.

## Milestone 5: Session and Development Workflow

- [ ] Define launch order and readiness checks for River, Triad, and Toasty.
- [ ] Give each process a separate log file under the XDG state directory.
- [ ] Forward termination signals and shut down children cleanly.
- [ ] Add bounded restart behavior for Triad and Toasty.
- [ ] Add development and release session tasks.
- [ ] Preserve WayVNC access while replacing individual components.
- [ ] Add a FreeBSD session entry or equivalent login command.
- [ ] Document required FreeBSD packages and runtime services.
- [ ] Reproduce the environment from a clean Toasty checkout.

## Milestone 6: Desktop Shell Features

- [ ] Application launcher and searchable command palette.
- [ ] Notification daemon and notification center.
- [ ] Overview driven by Triad's native state and commands.
- [ ] Window switcher and recent-window UI.
- [ ] Quick settings for audio, networking, brightness, and appearance.
- [ ] Session actions for lock, logout, restart, suspend, and poweroff.
- [ ] Wallpaper and desktop background surfaces.
- [ ] Multi-monitor placement, scaling, and hotplug behavior.
- [ ] Keyboard navigation and accessibility pass.

## Milestone 7: Hardening and Distribution

- [ ] Add unit tests for IPC, state reduction, and view models.
- [ ] Add integration tests for reconnects and malformed messages.
- [ ] Run long-lived River/Triad/Toasty sessions under ARC diagnostics.
- [ ] Verify behavior after Triad, Toasty, and WayVNC crashes.
- [ ] Pin release dependency revisions with Atlas.
- [ ] Add FreeBSD installation and upgrade instructions.
- [ ] Package configuration defaults, session files, and desktop assets.
- [ ] Define version compatibility for River, Triad, Merenda, and Toasty.

## MVP Definition

- [ ] One command starts River, Triad, Toasty, and the remote-view path.
- [ ] The session is visible and controllable through WayVNC.
- [ ] A Merenda panel shows outputs, workspaces, and the focused window.
- [ ] Workspace switching works through Toasty and Triad's native IPC.
- [ ] The three main processes can restart independently.
- [ ] A clean FreeBSD checkout builds with Atlas only.

## Immediate Next Step

- [ ] Audit the running FreeBSD Wayland session and installed River.
- [ ] Start the isolated River + Triad smoke session.
- [ ] Record the first successful launch command and logs.
