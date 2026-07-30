import std/[json, net, os]

import protocol, transport, types

type
  TriadClient* = ref object
    socketPath*: string
    transport*: TriadTransport

  TriadEventCallback* = proc(event: sink TriadEvent) {.closure.}
  TriadEventLineCallback* = proc(line: string) {.closure.}
  TriadConnectionCallback* = proc(connected: bool, error: string) {.closure.}
  TriadStopCallback* = proc(): bool {.closure.}

proc newTriadClient*(
    socketPath = defaultTriadSocketPath(), transport = newUnixTriadTransport()
): TriadClient =
  TriadClient(socketPath: socketPath, transport: transport)

proc fetchOutputs*(client: TriadClient): seq[TriadOutput] =
  client.transport.request(client.socketPath, outputsRequest()).parseOutputsReply()

proc fetchWorkspaces*(client: TriadClient): seq[TriadWorkspace] =
  client.transport.request(client.socketPath, workspacesRequest()).parseWorkspacesReply()

proc fetchWindows*(client: TriadClient): seq[TriadWindow] =
  client.transport.request(client.socketPath, windowsRequest()).parseWindowsReply()

proc fetchSnapshot*(client: TriadClient): TriadSnapshot =
  client.transport.request(client.socketPath, stateRequest()).parseSnapshotReply()

proc sendAckRequest(client: TriadClient, request: string) =
  client.transport.request(client.socketPath, request).parseAckReply()

proc focusWorkspace*(client: TriadClient, workspaceIdx: uint32) =
  client.sendAckRequest(
    actionRequest("focus-workspace", [("workspace_idx", %workspaceIdx)])
  )

proc focusWindow*(client: TriadClient, windowId: uint32) =
  client.sendAckRequest(actionRequest("focus-window", [("id", %windowId)]))

proc closeWindow*(client: TriadClient, windowId: uint32) =
  client.sendAckRequest(actionRequest("close-window", [("id", %windowId)]))

proc moveWindowToWorkspace*(
    client: TriadClient, windowId, workspaceIdx: uint32, follow = false
) =
  client.sendAckRequest(
    actionRequest(
      "move-window-to-workspace",
      [("id", %windowId), ("workspace_idx", %workspaceIdx), ("follow", %follow)],
    )
  )

proc setLayout*(client: TriadClient, layout: string, workspaceIdx = 0'u32) =
  client.sendAckRequest(setLayoutRequest(layout, workspaceIdx))

proc switchLayout*(client: TriadClient) =
  client.sendAckRequest(switchLayoutRequest())

proc hideHotkeyOverlay*(client: TriadClient) =
  client.sendAckRequest(actionRequest("hide-hotkey-overlay", []))

proc observeEventLines*(
    client: TriadClient,
    onEventLine: TriadEventLineCallback,
    onConnection: TriadConnectionCallback = nil,
    shouldStop: TriadStopCallback = nil,
    scopes: set[TriadEventScope] = {tesLayout, tesState, tesWindow},
    reconnectDelayMs = 250,
    receiveTimeoutMs = -1,
    maxAttempts = 0,
): int =
  var
    attempts = 0
    connectionReported = false
    lastConnected = false

  proc reportConnection(connected: bool, error: string) =
    if onConnection.isNil:
      return
    if not connectionReported or connected != lastConnected:
      onConnection(connected, error)
      connectionReported = true
      lastConnected = connected

  while maxAttempts <= 0 or attempts < maxAttempts:
    if not shouldStop.isNil and shouldStop():
      return
    inc attempts
    var stream: TriadStream
    try:
      stream =
        client.transport.openStream(client.socketPath, eventStreamRequest(scopes))
      stream.receiveLine(receiveTimeoutMs).parseAckReply()
      reportConnection(true, "")

      while shouldStop.isNil or not shouldStop():
        var line: string
        try:
          line = stream.receiveLine(receiveTimeoutMs)
        except TimeoutError:
          continue
        inc result
        if not onEventLine.isNil:
          onEventLine(line)
        if not shouldStop.isNil and shouldStop():
          return
    except CatchableError as error:
      reportConnection(false, error.msg)
    finally:
      stream.close()

    if maxAttempts > 0 and attempts >= maxAttempts:
      break
    if reconnectDelayMs > 0:
      sleep(reconnectDelayMs)

proc observe*(
    client: TriadClient,
    onEvent: TriadEventCallback,
    onConnection: TriadConnectionCallback = nil,
    shouldStop: TriadStopCallback = nil,
    scopes: set[TriadEventScope] = {tesLayout, tesState, tesWindow},
    reconnectDelayMs = 250,
    receiveTimeoutMs = -1,
    maxAttempts = 0,
): int =
  let onEventLine: TriadEventLineCallback = proc(line: string) =
    if not onEvent.isNil:
      var event = line.parseEvent()
      onEvent(move event)

  client.observeEventLines(
    onEventLine = onEventLine,
    onConnection = onConnection,
    shouldStop = shouldStop,
    scopes = scopes,
    reconnectDelayMs = reconnectDelayMs,
    receiveTimeoutMs = receiveTimeoutMs,
    maxAttempts = maxAttempts,
  )
