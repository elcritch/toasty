import std/[json, options, os, unittest]

import toasty/triad
import support/faketriadtransport

const Ack = """{"ok":true,"triad":{"version":1,"type":"ack"}}"""

proc fixture(name: string): string =
  readFile(currentSourcePath().parentDir() / "fixtures" / name)

suite "Triad IPC client":
  test "fetches a snapshot through an injected transport":
    let fake = newScriptedTriadTransport(replies = @[fixture("triad_state.json")])
    let client = newTriadClient("/fake/triad.sock", fake.asTransport())

    let snapshot = client.fetchSnapshot()

    check snapshot.outputs[0].name == "HEADLESS-1"
    check fake.requests.len == 1
    check parseJson(fake.requests[0])["triad"]["request"].getStr() == "state"

  test "typed command wrappers send native action requests":
    let fake = newScriptedTriadTransport(replies = @[Ack, Ack, Ack, Ack, Ack, Ack, Ack])
    let client = newTriadClient("/fake/triad.sock", fake.asTransport())

    client.focusWorkspace(2)
    client.focusWindow(42)
    client.moveWindowToWorkspace(42, 3, follow = true)
    client.setLayout("tile", workspaceIdx = 3)
    client.switchLayout()
    client.closeWindow(42)
    client.hideHotkeyOverlay()

    check fake.requests.len == 7
    let focusWorkspace = parseJson(fake.requests[0])["triad"]
    check focusWorkspace["action"].getStr() == "focus-workspace"
    check focusWorkspace["workspace_idx"].getInt() == 2
    let moveWindow = parseJson(fake.requests[2])["triad"]
    check moveWindow["action"].getStr() == "move-window-to-workspace"
    check moveWindow["follow"].getBool()
    check parseJson(fake.requests[3])["triad"]["request"].getStr() == "set-layout"
    check parseJson(fake.requests[4])["triad"]["request"].getStr() == "switch-layout"
    check parseJson(fake.requests[5])["triad"]["action"].getStr() == "close-window"
    let overlayAction = parseJson(fake.requests[6])["triad"]["action"].getStr()
    check overlayAction == "hide-hotkey-overlay"

  test "raw observer forwards complete event lines for thread dispatch":
    let fake =
      newScriptedTriadTransport(streams = @[@[Ack, fixture("triad_layout_event.json")]])
    let client = newTriadClient("/fake/triad.sock", fake.asTransport())
    var lines: seq[string]
    let onEventLine: TriadEventLineCallback = proc(line: string) =
      lines.add(line)

    let eventCount = client.observeEventLines(
      onEventLine = onEventLine, reconnectDelayMs = 0, maxAttempts = 1
    )

    check eventCount == 1
    check lines == @[fixture("triad_layout_event.json")]

  test "event observer reconnects and continues reducing state":
    let fake = newScriptedTriadTransport(
      replies = @[fixture("triad_state.json")],
      streams = @[
        @[Ack, fixture("triad_layout_event.json")],
        @[Ack, fixture("triad_window_event.json")],
      ],
    )
    let client = newTriadClient("/fake/triad.sock", fake.asTransport())
    var
      state = initTriadShellState(client.fetchSnapshot())
      connectionStates: seq[bool]
      errors: seq[string]

    let onEvent: TriadEventCallback = proc(event: sink TriadEvent) =
      state.apply(event)
    let onConnection = proc(connected: bool, error: string) =
      connectionStates.add(connected)
      if error.len > 0:
        errors.add(error)
    let eventCount = client.observe(
      onEvent = onEvent,
      onConnection = onConnection,
      reconnectDelayMs = 0,
      maxAttempts = 2,
    )

    check eventCount == 2
    check fake.streamIndex == 2
    check fake.closedStreams == 2
    check connectionStates == @[true, false, true, false]
    check errors.len == 2
    check state.activeWorkspaceIdx == 2
    check state.windows[0].title == some("Toasty probe updated")
    let subscription = parseJson(fake.subscriptions[0])["triad"]
    check subscription["request"].getStr() == "event-stream"
    check subscription["events"].getElems() == @[%"layout", %"state", %"window"]

  test "reports one disconnected transition across repeated connection failures":
    let fake = newScriptedTriadTransport()
    let client = newTriadClient("/fake/triad.sock", fake.asTransport())
    var connectionStates: seq[bool]
    let onEvent: TriadEventCallback = proc(event: sink TriadEvent) =
      discard event
    let onConnection = proc(connected: bool, error: string) =
      discard error
      connectionStates.add(connected)

    discard client.observe(
      onEvent = onEvent,
      onConnection = onConnection,
      reconnectDelayMs = 0,
      maxAttempts = 3,
    )

    check connectionStates == @[false]
