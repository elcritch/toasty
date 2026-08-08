import std/[options, os, unittest]

import toasty

proc fixture(name: string): string =
  readFile(currentSourcePath().parentDir() / "fixtures" / name)

suite "desktop shell model":
  test "ranks prefix matches ahead of fuzzy matches":
    check searchScore("term", "Terminal", "") >
      searchScore("term", "System Monitor", "terminal")
    check searchScore("tbr", "Toasty Browser", "") >= 0
    check searchScore("missing", "Terminal", "") < 0

  test "combines applications commands and Triad windows in the palette":
    let
      state = initTriadShellState(fixture("triad_state.json").parseSnapshotReply())
      applications =
        @[DesktopApplication(id: "foot", name: "Terminal", comment: "Open a shell")]

    check paletteResults(applications, state, "overview")[0].command == pcShowOverview
    check paletteResults(applications, state, "terminal")[0].kind == pikApplication
    check paletteResults(applications, state, "probe")[0].windowId == 4278190084'u32

  test "tracks recent focused windows for the switcher":
    var state = initTriadShellState(fixture("triad_state.json").parseSnapshotReply())
    state.windows.add(
      TriadWindow(
        id: 7, title: some("Second"), appId: some("second"), workspaceIdx: some(1'u32)
      )
    )
    var navigation: ShellNavigation
    navigation.noteFocusedWindow(state)
    state.windows[0].isFocused = false
    state.windows[1].isFocused = true
    navigation.noteFocusedWindow(state)

    let windows = state.windowSwitcherItems(navigation.recentWindows)
    check windows[0].id == 7
    check windows[1].id == 4278190084'u32

  test "builds scaled per-output overview models":
    var state = initTriadShellState(fixture("triad_state.json").parseSnapshotReply())
    state.outputs[0].scale = 2.0
    state.outputs[0].isPrimary = true

    let outputs = state.overviewOutputs()
    check outputs.len == 1
    check outputs[0].logicalWidth == 640
    check outputs[0].logicalHeight == 360
    check outputs[0].workspaces[0].windows[0].title == "Toasty probe"

  test "wraps keyboard selection in both directions":
    var navigation: ShellNavigation
    navigation.selectPrevious(3)
    check navigation.selectedIndex == 2
    navigation.selectNext(3)
    check navigation.selectedIndex == 0
