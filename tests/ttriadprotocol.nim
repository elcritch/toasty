import std/[json, options, os, unittest]

import toasty/triad

proc fixture(name: string): string =
  readFile(currentSourcePath().parentDir() / "fixtures" / name)

suite "Triad IPC protocol":
  test "parses representative output workspace and window replies":
    let
      outputs = fixture("triad_outputs.json").parseOutputsReply()
      workspaces = fixture("triad_workspaces.json").parseWorkspacesReply()
      windows = fixture("triad_windows.json").parseWindowsReply()

    check outputs.len == 1
    check outputs[0].id == 4278190082'u32
    check outputs[0].name == "HEADLESS-1"
    check outputs[0].geometry.width == 1280
    check workspaces.len == 2
    check workspaces[0].name == some("main")
    check workspaces[1].name.isNone
    check workspaces[0].focusedWindowId == some(4278190084'u32)
    check windows.len == 1
    check windows[0].title == some("Toasty probe")
    check windows[0].actualSize.height == 656
    check windows[0].parentId.isNone

  test "parses a complete shell snapshot":
    let snapshot = fixture("triad_state.json").parseSnapshotReply()

    check snapshot.version == TriadIpcVersion
    check snapshot.activeWorkspaceIdx == 1
    check snapshot.outputs.len == 1
    check snapshot.workspaces.len == 1
    check snapshot.windows.len == 1
    check snapshot.windows[0].isFocused

  test "parses incremental events and reduces shell state":
    let snapshot = fixture("triad_state.json").parseSnapshotReply()
    var state = initTriadShellState(snapshot)

    let layoutEvent = fixture("triad_layout_event.json").parseEvent()
    check layoutEvent.kind == tekLayoutStateChanged
    state.apply(layoutEvent)
    check state.activeWorkspaceIdx == 2
    check state.workspaces[0].workspaceIdx == 2

    let windowEvent = fixture("triad_window_event.json").parseEvent()
    check windowEvent.kind == tekWindowChanged
    state.apply(windowEvent)
    check state.windows.len == 1
    check state.windows[0].title == some("Toasty probe updated")
    check state.windows[0].workspaceIdx == some(2'u32)

  test "builds versioned snapshot event and command requests":
    let state = parseJson(stateRequest())
    check state["triad"]["version"].getInt() == 1
    check state["triad"]["request"].getStr() == "state"

    let stream = parseJson(eventStreamRequest({tesLayout, tesState, tesWindow}))
    check stream["triad"]["events"].getElems() == @[%"layout", %"state", %"window"]

    let focus = parseJson(actionRequest("focus-workspace", [("workspace_idx", %2)]))
    check focus["triad"]["request"].getStr() == "action"
    check focus["triad"]["action"].getStr() == "focus-workspace"
    check focus["triad"]["workspace_idx"].getInt() == 2

    let layout = parseJson(setLayoutRequest("tile", workspaceIdx = 2))
    check layout["triad"]["request"].getStr() == "set-layout"
    check layout["triad"]["target"]["workspace_idx"].getInt() == 2

  test "rejects an unsupported IPC version":
    var payload = parseJson(fixture("triad_outputs.json"))
    payload["triad"]["version"] = %2

    expect TriadProtocolError:
      discard ($payload).parseOutputsReply()
