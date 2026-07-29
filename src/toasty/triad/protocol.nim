import std/[json, options]

import types

proc fail(message: string) {.noreturn.} =
  raise newException(TriadProtocolError, message)

proc requiredField(node: JsonNode, name: string): JsonNode =
  if node.kind != JObject or not node.hasKey(name):
    fail("missing Triad field: " & name)
  node[name]

proc requiredObject(node: JsonNode, name: string): JsonNode =
  result = node.requiredField(name)
  if result.kind != JObject:
    fail("Triad field must be an object: " & name)

proc requiredArray(node: JsonNode, name: string): JsonNode =
  result = node.requiredField(name)
  if result.kind != JArray:
    fail("Triad field must be an array: " & name)

proc requiredString(node: JsonNode, name: string): string =
  let value = node.requiredField(name)
  if value.kind != JString:
    fail("Triad field must be a string: " & name)
  value.getStr()

proc requiredBool(node: JsonNode, name: string): bool =
  let value = node.requiredField(name)
  if value.kind != JBool:
    fail("Triad field must be a boolean: " & name)
  value.getBool()

proc requiredInt(node: JsonNode, name: string): int =
  let value = node.requiredField(name)
  if value.kind != JInt:
    fail("Triad field must be an integer: " & name)
  value.getInt()

proc requiredInt32(node: JsonNode, name: string): int32 =
  let value = node.requiredInt(name)
  if value < int(low(int32)) or value > int(high(int32)):
    fail("Triad field is outside int32 range: " & name)
  value.int32

proc requiredUint32(node: JsonNode, name: string): uint32 =
  let value = node.requiredInt(name)
  if value < 0 or uint64(value) > uint64(high(uint32)):
    fail("Triad field is outside uint32 range: " & name)
  value.uint32

proc requiredFloat32(node: JsonNode, name: string): float32 =
  let value = node.requiredField(name)
  case value.kind
  of JFloat:
    value.getFloat().float32
  of JInt:
    value.getInt().float32
  else:
    fail("Triad field must be numeric: " & name)

proc optionalString(node: JsonNode, name: string): Option[string] =
  let value = node.requiredField(name)
  case value.kind
  of JNull:
    none(string)
  of JString:
    some(value.getStr())
  else:
    fail("Triad field must be a string or null: " & name)

proc optionalUint32(node: JsonNode, name: string): Option[uint32] =
  let value = node.requiredField(name)
  case value.kind
  of JNull:
    none(uint32)
  of JInt:
    let number = value.getInt()
    if number < 0 or uint64(number) > uint64(high(uint32)):
      fail("Triad field is outside uint32 range: " & name)
    some(number.uint32)
  else:
    fail("Triad field must be an integer or null: " & name)

proc optionalInt32(node: JsonNode, name: string): Option[int32] =
  let value = node.requiredField(name)
  case value.kind
  of JNull:
    none(int32)
  of JInt:
    let number = value.getInt()
    if number < int(low(int32)) or number > int(high(int32)):
      fail("Triad field is outside int32 range: " & name)
    some(number.int32)
  else:
    fail("Triad field must be an integer or null: " & name)

proc parseGeometry(node: JsonNode): TriadGeometry =
  if node.kind != JObject:
    fail("Triad geometry must be an object")
  TriadGeometry(
    x: node.requiredInt32("x"),
    y: node.requiredInt32("y"),
    width: node.requiredInt32("width"),
    height: node.requiredInt32("height"),
  )

proc parseSize(node: JsonNode): TriadSize =
  if node.kind != JObject:
    fail("Triad size must be an object")
  TriadSize(width: node.requiredInt32("width"), height: node.requiredInt32("height"))

proc parseOutput*(node: JsonNode): TriadOutput =
  TriadOutput(
    id: node.requiredUint32("id"),
    name: node.requiredString("name"),
    connected: node.requiredBool("connected"),
    isPrimary: node.requiredBool("is_primary"),
    refreshRate: node.requiredInt32("refresh_rate"),
    physicalWidth: node.requiredInt32("physical_width"),
    physicalHeight: node.requiredInt32("physical_height"),
    scale: node.requiredFloat32("scale"),
    transform: node.requiredString("transform"),
    geometry: node.requiredObject("geometry").parseGeometry(),
  )

proc parseWorkspace*(node: JsonNode): TriadWorkspace =
  TriadWorkspace(
    tagId: node.requiredUint32("tag_id"),
    workspaceIdx: node.requiredUint32("workspace_idx"),
    name: node.optionalString("name"),
    output: node.optionalString("output"),
    layout: node.requiredString("layout"),
    layoutKind: node.requiredString("layout_kind"),
    runtimeKind: node.requiredString("runtime_kind"),
    layoutSource: node.requiredString("layout_source"),
    fallbackLayout: node.requiredString("fallback_layout"),
    isConfigured: node.requiredBool("is_configured"),
    isActive: node.requiredBool("is_active"),
    isOutputVisible: node.requiredBool("is_output_visible"),
    isUrgent: node.requiredBool("is_urgent"),
    occupied: node.requiredBool("occupied"),
    focusedWindowId: node.optionalUint32("focused_window_id"),
  )

proc parseWindow*(node: JsonNode): TriadWindow =
  let position = node.requiredObject("position")
  TriadWindow(
    id: node.requiredUint32("id"),
    pid: node.optionalInt32("pid"),
    parentId: node.optionalUint32("parent_id"),
    title: node.optionalString("title"),
    appId: node.optionalString("app_id"),
    tagId: node.optionalUint32("tag_id"),
    workspaceIdx: node.optionalUint32("workspace_idx"),
    output: node.optionalString("output"),
    position: TriadWindowPosition(
      columnIdx: position.optionalUint32("column_idx"),
      windowIdx: position.optionalUint32("window_idx"),
    ),
    isFocused: node.requiredBool("is_focused"),
    isFloating: node.requiredBool("is_floating"),
    isMaximized: node.requiredBool("is_maximized"),
    isMinimized: node.requiredBool("is_minimized"),
    isSticky: node.requiredBool("is_sticky"),
    isOverlay: node.requiredBool("is_overlay"),
    isUnmanagedGlobal: node.requiredBool("is_unmanaged_global"),
    isFullscreen: node.requiredBool("is_fullscreen"),
    fullscreenOutput: node.optionalUint32("fullscreen_output"),
    widthProportion: node.requiredFloat32("width_proportion"),
    heightProportion: node.requiredFloat32("height_proportion"),
    actualSize: node.requiredObject("actual_size").parseSize(),
    floatingGeometry: node.requiredObject("floating_geometry").parseGeometry(),
    keyboardShortcutsInhibit: node.requiredBool("keyboard_shortcuts_inhibit"),
    idleInhibit: node.requiredString("idle_inhibit"),
    isTerminal: node.requiredBool("is_terminal"),
    allowSwallow: node.requiredBool("allow_swallow"),
    swallowedBy: node.optionalUint32("swallowed_by"),
    swallowing: node.optionalUint32("swallowing"),
  )

proc parseOutputs(node: JsonNode): seq[TriadOutput] =
  if node.kind != JArray:
    fail("Triad outputs must be an array")
  for output in node:
    result.add(output.parseOutput())

proc parseWorkspaces(node: JsonNode): seq[TriadWorkspace] =
  if node.kind != JArray:
    fail("Triad workspaces must be an array")
  for workspace in node:
    result.add(workspace.parseWorkspace())

proc parseWindows(node: JsonNode): seq[TriadWindow] =
  if node.kind != JArray:
    fail("Triad windows must be an array")
  for window in node:
    result.add(window.parseWindow())

proc parseJsonLine(line: string): JsonNode =
  try:
    result = parseJson(line)
  except CatchableError as error:
    fail("invalid Triad JSON: " & error.msg)
  if result.kind != JObject:
    fail("Triad message must be an object")

proc checkVersion(node: JsonNode) =
  let version = node.requiredUint32("version")
  if version != TriadIpcVersion:
    fail("unsupported Triad IPC version: " & $version)

proc replyPayload(line, expectedType: string): JsonNode =
  let root = line.parseJsonLine()
  if not root.requiredBool("ok"):
    let message =
      if root.hasKey("error") and root["error"].kind == JString:
        root["error"].getStr()
      else:
        "Triad request failed"
    fail(message)
  result = root.requiredObject("triad")
  result.checkVersion()
  if result.requiredString("type") != expectedType:
    fail("unexpected Triad reply type; expected " & expectedType)

proc parseOutputsReply*(line: string): seq[TriadOutput] =
  line.replyPayload("outputs").requiredArray("outputs").parseOutputs()

proc parseWorkspacesReply*(line: string): seq[TriadWorkspace] =
  line.replyPayload("workspaces").requiredArray("workspaces").parseWorkspaces()

proc parseWindowsReply*(line: string): seq[TriadWindow] =
  line.replyPayload("windows").requiredArray("windows").parseWindows()

proc parseSnapshotNode(node: JsonNode): TriadSnapshot =
  let layout = node.requiredObject("layout")
  result = TriadSnapshot(
    version: node.requiredUint32("version"),
    activeTag: layout.requiredUint32("active_tag"),
    activeWorkspaceIdx: layout.requiredUint32("active_workspace_idx"),
    outputs: node.requiredArray("outputs").parseOutputs(),
    workspaces: layout.requiredArray("workspaces").parseWorkspaces(),
    windows: node.requiredArray("windows").parseWindows(),
  )
  if result.version != TriadIpcVersion:
    fail("unsupported Triad state version: " & $result.version)

proc parseSnapshotReply*(line: string): TriadSnapshot =
  line.replyPayload("state").requiredObject("state").parseSnapshotNode()

proc parseAckReply*(line: string) =
  discard line.replyPayload("ack")

proc parseEvent*(line: string): TriadEvent =
  let root = line.parseJsonLine()
  let payload = root.requiredObject("triad")
  payload.checkVersion()
  let eventName = payload.requiredString("event")
  case eventName
  of "layout-state-changed":
    let state = payload.requiredObject("state")
    result = TriadEvent(
      kind: tekLayoutStateChanged,
      activeTag: state.requiredUint32("active_tag"),
      activeWorkspaceIdx: state.requiredUint32("active_workspace_idx"),
      workspaces: state.requiredArray("workspaces").parseWorkspaces(),
    )
  of "state-changed":
    result = TriadEvent(
      kind: tekStateChanged,
      snapshot: payload.requiredObject("state").parseSnapshotNode(),
    )
  of "window-changed":
    result = TriadEvent(
      kind: tekWindowChanged,
      window: some(payload.requiredObject("window").parseWindow()),
    )
  of "capture-sessions-changed":
    discard payload.requiredArray("capture_sessions")
    result = TriadEvent(kind: tekCaptureSessionsChanged)
  else:
    fail("unsupported Triad event: " & eventName)

proc requestPayload(request: string): JsonNode =
  %*{"triad": {"version": TriadIpcVersion, "request": request}}

proc stateRequest*(): string =
  $requestPayload("state")

proc outputsRequest*(): string =
  $requestPayload("outputs")

proc workspacesRequest*(): string =
  $requestPayload("workspaces")

proc windowsRequest*(): string =
  $requestPayload("windows")

proc eventStreamRequest*(scopes: set[TriadEventScope]): string =
  var events = newJArray()
  for scope in TriadEventScope:
    if scope notin scopes:
      continue
    events.add(
      %(
        case scope
        of tesLayout: "layout"
        of tesState: "state"
        of tesWindow: "window"
        of tesCapture: "capture"
      )
    )
  var payload = requestPayload("event-stream")
  payload["triad"]["events"] = events
  $payload

proc actionRequest*(action: string, fields: openArray[(string, JsonNode)]): string =
  var payload = requestPayload("action")
  var triad = payload["triad"]
  triad["action"] = %action
  for field in fields:
    triad.add(field[0], field[1])
  $payload

proc setLayoutRequest*(layout: string, workspaceIdx = 0'u32): string =
  var payload = requestPayload("set-layout")
  payload["triad"]["layout"] = %layout
  if workspaceIdx > 0:
    payload["triad"]["target"] = %*{"workspace_idx": workspaceIdx}
  $payload

proc switchLayoutRequest*(): string =
  $requestPayload("switch-layout")
