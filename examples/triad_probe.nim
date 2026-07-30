import std/[options, os, strutils]

import toasty/triad

type ProbeOptions = object
  socketPath: string
  watch: bool
  eventLimit: int
  reconnectDelayMs: int

proc usage() =
  echo """Usage: triad_probe [options]

Print a typed snapshot from Triad's native IPC socket.

Options:
  --socket:PATH        override TRIAD_SOCKET/XDG_RUNTIME_DIR discovery
  --watch              observe layout, state, and window events
  --events:N           stop after N events (implies --watch)
  --reconnect-ms:N     reconnect delay after a Triad restart (default: 250)
  -h, --help           show this help"""

proc optionValue(argument, name: string): Option[string] =
  for separator in [":", "="]:
    let prefix = "--" & name & separator
    if argument.startsWith(prefix):
      return some(argument[prefix.len .. ^1])

proc positiveInt(value, optionName: string, allowZero = false): int =
  try:
    result = parseInt(value)
  except ValueError:
    raise newException(ValueError, optionName & " requires an integer")
  if result < 0 or (not allowZero and result == 0):
    raise newException(ValueError, optionName & " requires a positive integer")

proc parseOptions(): ProbeOptions =
  result = ProbeOptions(socketPath: defaultTriadSocketPath(), reconnectDelayMs: 250)
  for argument in commandLineParams():
    if argument in ["-h", "--help"]:
      usage()
      quit(QuitSuccess)
    elif argument == "--watch":
      result.watch = true
    elif argument.optionValue("socket").isSome:
      result.socketPath = argument.optionValue("socket").get()
    elif argument.optionValue("events").isSome:
      result.eventLimit = positiveInt(argument.optionValue("events").get(), "--events")
      result.watch = true
    elif argument.optionValue("reconnect-ms").isSome:
      result.reconnectDelayMs = positiveInt(
        argument.optionValue("reconnect-ms").get(), "--reconnect-ms", allowZero = true
      )
    else:
      raise newException(ValueError, "unknown option: " & argument)

proc display(value: Option[string]): string =
  if value.isSome:
    value.get()
  else:
    "-"

proc printState(state: TriadShellState) =
  echo "socket state: active workspace ", state.activeWorkspaceIdx
  echo "outputs (", state.outputs.len, ")"
  for output in state.outputs:
    echo "  ",
      output.name, " ", output.geometry.width, "x", output.geometry.height, " scale=",
      output.scale
  echo "workspaces (", state.workspaces.len, ")"
  for workspace in state.workspaces:
    echo "  ",
      workspace.workspaceIdx,
      " name=",
      workspace.name.display(),
      " output=",
      workspace.output.display(),
      " layout=",
      workspace.layout,
      " active=",
      workspace.isActive,
      " occupied=",
      workspace.occupied
  echo "windows (", state.windows.len, ")"
  for window in state.windows:
    echo "  ",
      window.id,
      " app_id=",
      window.appId.display(),
      " title=",
      window.title.display(),
      " focused=",
      window.isFocused

proc eventName(kind: TriadEventKind): string =
  case kind
  of tekLayoutStateChanged: "layout-state-changed"
  of tekStateChanged: "state-changed"
  of tekWindowChanged: "window-changed"
  of tekCaptureSessionsChanged: "capture-sessions-changed"

proc main() =
  let options = parseOptions()
  let client = newTriadClient(options.socketPath)
  var state = initTriadShellState(client.fetchSnapshot())
  echo "Triad socket: ", options.socketPath
  state.printState()

  if not options.watch:
    return

  var received = 0
  let onEvent: TriadEventCallback = proc(event: sink TriadEvent) =
    state.apply(event)
    inc received
    echo "event ",
      received,
      ": ",
      event.kind.eventName(),
      " active_workspace=",
      state.activeWorkspaceIdx,
      " windows=",
      state.windows.len
  let onConnection = proc(connected: bool, error: string) =
    if connected:
      echo "subscription: connected"
    else:
      echo "subscription: disconnected: ", error
  let shouldStop = proc(): bool =
    options.eventLimit > 0 and received >= options.eventLimit
  discard client.observe(
    onEvent = onEvent,
    onConnection = onConnection,
    shouldStop = shouldStop,
    reconnectDelayMs = options.reconnectDelayMs,
  )

when isMainModule:
  try:
    main()
  except CatchableError as error:
    stderr.writeLine("triad_probe: " & error.msg)
    quit(QuitFailure)
