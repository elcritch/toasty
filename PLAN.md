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

- [x] Record the installed River and WayVNC versions.
- [x] Record the active `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`, seat, and backend.
- [x] Confirm which compositor currently owns the WayVNC-visible session.
- [x] Verify that River exposes every protocol required by the current Triad
      checkout.
- [x] Decide whether the development session should be nested or replace the
      current compositor.
- [x] Start an isolated headless River session with an explicit replacement
      guard for the existing remote desktop.
- [x] Start `deps/triad/triad` as River's external manager.
- [x] Launch simple Wayland clients and confirm Triad manages them.
- [x] Exercise focus, workspace, and layout commands through `triad msg`.
- [x] Confirm the complete session is visible and interactive through WayVNC.
- [x] Capture logs and document the exact environment and launch command.
- [x] Add a repeatable `nim sessionSmoke` task.

Exit criteria:

- [x] River, Triad, a test client, and WayVNC work together for a complete
      interactive smoke test.
- [x] The smoke session can be started again from one documented command.

## Milestone 2: Merenda Wayland Shell Surface

Resolve the largest UI risk early: desktop panels and overlays need layer-shell
semantics rather than ordinary application windows.

- [x] Add Merenda to `toasty.nimble` through Atlas.
- [x] Confirm Merenda's current Siwin backend behavior under River.
- [x] Audit support for transparency, undecorated windows, output selection,
      scaling, keyboard interactivity, and pointer input.
- [x] Audit support for `wlr-layer-shell`, anchors, margins, exclusive zones,
      and per-output surfaces.
- [x] Build a minimal layer-shell surface with a solid Merenda-rendered panel.
- [x] Decide whether layer-shell support belongs in Siwin, Merenda, or a small
      Toasty Wayland host adapter.
- [x] Add a focused test or example for the chosen surface integration.

Exit criteria:

- [x] A Merenda-rendered panel surface appears on a chosen River output.
- [x] The panel reserves space and receives pointer input correctly.
- [x] The integration direction is documented before broader UI work starts.

## Milestone 3: Typed Triad IPC Client

Give Toasty a narrow, testable boundary to the external window manager.

- [x] Document Triad's native socket discovery and connection lifecycle.
- [x] Capture representative workspace, window, output, and event payloads.
- [x] Define Toasty types for the shell state actually needed by the UI.
- [x] Implement snapshot requests and event subscriptions.
- [x] Implement focus, workspace, layout, and window commands.
- [x] Add reconnect behavior for Triad restarts and socket replacement.
- [x] Keep parsing and transport separate from Merenda views.
- [x] Add deterministic parser tests using captured payloads.
- [x] Add a fake transport for shell view-model tests.

Exit criteria:

- [x] A command-line Toasty probe prints live outputs, workspaces, and windows.
- [x] The probe observes changes and survives a Triad restart.

## Milestone 4: First Vertical Slice

Build one useful shell component end to end before expanding the desktop.

- [x] Show one panel per output.
- [x] Display workspace names and active state from Triad IPC.
- [x] Display the focused application's title.
- [x] Focus a workspace when its panel item is clicked.
- [x] Update the panel from subscriptions without polling.
- [x] Handle output add/remove events.
- [x] Apply a basic Merenda theme and FreeBSD-appropriate font fallback.
- [x] Disable or avoid overlapping Triad shell overlays.
- [x] Verify the slice visually and interactively through WayVNC.

Exit criteria:

- [x] The panel is usable for workspace navigation during a real River session.
- [x] River, Triad, or Toasty can restart independently without losing the
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

- [x] Add Merenda to `toasty.nimble` through Atlas.
- [x] Confirm Merenda's current Siwin backend behavior under River.
- [x] Audit support for transparency, input, scaling, and output selection.
- [x] Audit the existing Siwin and Merenda layer-shell integration.
- [x] Build a minimal layer-shell surface with a solid Merenda-rendered panel.
- [x] Document Triad's native socket discovery and connection lifecycle.
- [x] Show one panel per output.
