import std/[options, os, unittest]

import toasty

proc fixture(name: string): string =
  readFile(currentSourcePath().parentDir() / "fixtures" / name)

suite "panel view model":
  test "maps Triad workspaces and focused title onto each connected output":
    var state = initTriadShellState(fixture("triad_state.json").parseSnapshotReply())
    state.outputs.add(TriadOutput(id: 9, name: "DP-1", connected: true, scale: 2.0))
    state.workspaces.add(
      TriadWorkspace(
        tagId: 2,
        workspaceIdx: 2,
        name: none(string),
        output: some("DP-1"),
        isActive: false,
        occupied: false,
      )
    )

    let panels = state.panelViewModels()

    check panels.len == 2
    check panels[0].outputName == "HEADLESS-1"
    check panels[0].outputIndex == 0
    check panels[0].outputWidth == 1280
    check panels[0].outputHeight == 720
    check panels[0].outputScale == 1.0
    check panels[0].workspaces[0].label == "main"
    check panels[0].workspaces[0].active
    check panels[0].focusedTitle == "Toasty probe"
    check panels[1].outputName == "DP-1"
    check panels[1].outputIndex == 1
    check panels[1].workspaces[0].label == "2"

  test "uses logical output dimensions at fractional and integer scale":
    var state = initTriadShellState(fixture("triad_state.json").parseSnapshotReply())
    state.outputs[0].scale = 2.0

    let panel = state.panelViewModels()[0]
    check panel.outputWidth == 640
    check panel.outputHeight == 360

  test "removes disconnected outputs and compacts layer output indices":
    var state = initTriadShellState(fixture("triad_state.json").parseSnapshotReply())
    state.outputs.insert(TriadOutput(id: 8, name: "HDMI-A-1", connected: false), 0)

    let panels = state.panelViewModels(connected = false)

    check panels.len == 1
    check panels[0].outputName == "HEADLESS-1"
    check panels[0].outputIndex == 0
    check not panels[0].connected

  test "falls back from an empty title to app ID and then Desktop":
    var state = initTriadShellState(fixture("triad_state.json").parseSnapshotReply())
    state.windows[0].title = some("  ")
    state.windows[0].appId = some("org.example.App")
    check state.panelViewModels()[0].focusedTitle == "org.example.App"

    state.windows[0].isFocused = false
    check state.panelViewModels()[0].focusedTitle == "Desktop"
