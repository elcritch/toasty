## Toasty desktop-shell orchestration and Triad observation lifecycle.

import std/[atomics, os, strutils]

import merenda/nimkit
import sigils
import sigils/selectors

import desktopentries, notificationdaemon, notifications, panelconfig, shellui, triad

const
  ObserverReceiveTimeoutMs = 100
  ObserverReconnectDelayMs = 250

type
  ShellMessageKind = enum
    smEvent
    smSnapshot
    smConnection

  ShellMessage = object
    case kind: ShellMessageKind
    of smEvent:
      event: TriadEvent
    of smSnapshot:
      snapshot: TriadSnapshot
    of smConnection:
      connected: bool

  ShellController = ref object of Agent
    client: TriadClient
    ui: ShellUi
    messageQueue: ptr Channel[ShellMessage]

  ObserverDispatcher = ref object of Agent

  TriadObserverWorker = ref object of AgentActor
    socketPath: string
    stopFlag: ptr Atomic[bool]
    messageQueue: ptr Channel[ShellMessage]

var processStopFlag: ptr Atomic[bool]

proc observationRequested*(dispatcher: ObserverDispatcher) {.signal.}
proc triadMessagesAvailable*(worker: TriadObserverWorker) {.signal.}

proc requestProcessStop() {.noconv.} =
  if not processStopFlag.isNil:
    processStopFlag[].store(true, moRelaxed)

proc environmentInt(name: string, fallback: int32): int32 =
  let value = getEnv(name)
  if value.len == 0:
    return fallback
  value.parseInt().int32

proc shellPanelConfig(): PanelConfig =
  result = defaultPanelConfig()
  result.height = environmentInt("TOASTY_PANEL_HEIGHT", result.height)
  result.margin = environmentInt("TOASTY_PANEL_MARGIN", result.margin)
  result.validate()

proc installFreeBsdFontFallback() =
  if getEnv(NimKitFontEnv).len > 0 or getEnv(MerendaFontEnv).len > 0:
    return
  for path in [
    "/usr/local/share/fonts/noto/NotoSans-Regular.ttf",
    "/usr/local/share/fonts/dejavu/DejaVuSans.ttf",
  ]:
    if fileExists(path):
      putEnv(NimKitFontEnv, path)
      stderr.writeLine("shell-font: ", path)
      return

proc shellCallbacks(client: TriadClient): ShellUiCallbacks =
  result.focusWorkspace = proc(workspaceIdx: uint32) =
    try:
      client.focusWorkspace(workspaceIdx)
      stderr.writeLine("shell-command: focus-workspace ", workspaceIdx)
    except CatchableError as error:
      stderr.writeLine("shell-command-error: ", error.msg)
  result.focusWindow = proc(windowId: uint32) =
    try:
      client.focusWindow(windowId)
      stderr.writeLine("shell-command: focus-window ", windowId)
    except CatchableError as error:
      stderr.writeLine("shell-command-error: ", error.msg)
  result.launchApplication = proc(application: DesktopApplication) =
    try:
      application.launch()
      stderr.writeLine("application-launched: ", application.id)
    except CatchableError as error:
      stderr.writeLine("application-launch-error: ", error.msg)

proc receiveTriadMessages(controller: ShellController) {.slot.} =
  while true:
    var received = controller.messageQueue[].tryRecv()
    if not received.dataAvailable:
      break
    case received.msg.kind
    of smEvent:
      controller.ui.applyEvent(received.msg.event)
    of smSnapshot:
      let state = initTriadShellState(received.msg.snapshot)
      controller.ui.updateState(state, connected = true)
    of smConnection:
      controller.ui.setConnected(received.msg.connected)
      stderr.writeLine(
        "triad-subscription: ",
        (if received.msg.connected: "connected" else: "disconnected"),
      )

proc observeTriad(worker: TriadObserverWorker) {.slot.} =
  let client = newTriadClient(worker.socketPath)
  let onEvent: TriadEventCallback = proc(event: sink TriadEvent) =
    worker.messageQueue[].send(ShellMessage(kind: smEvent, event: move event))
    emit worker.triadMessagesAvailable()
  let onConnection: TriadConnectionCallback = proc(connected: bool, error: string) =
    if connected:
      try:
        client.hideHotkeyOverlay()
        stderr.writeLine("hotkey-overlay: hidden")
      except CatchableError as overlayError:
        stderr.writeLine("hotkey-overlay-error: ", overlayError.msg)
      try:
        var snapshot = client.fetchSnapshot()
        worker.messageQueue[].send(
          ShellMessage(kind: smSnapshot, snapshot: move snapshot)
        )
      except CatchableError as snapshotError:
        stderr.writeLine("triad-snapshot-error: ", snapshotError.msg)
    elif error.len > 0:
      stderr.writeLine("triad-subscription-error: ", error)
    worker.messageQueue[].send(ShellMessage(kind: smConnection, connected: connected))
    emit worker.triadMessagesAvailable()
  let shouldStop: TriadStopCallback = proc(): bool =
    worker.stopFlag[].load(moRelaxed)

  discard client.observe(
    onEvent = onEvent,
    onConnection = onConnection,
    shouldStop = shouldStop,
    reconnectDelayMs = ObserverReconnectDelayMs,
    receiveTimeoutMs = ObserverReceiveTimeoutMs,
  )

proc runToastyShell*() =
  installFreeBsdFontFallback()
  let
    stopFlag = cast[ptr Atomic[bool]](allocShared0(sizeof(Atomic[bool])))
    messageQueue =
      cast[ptr Channel[ShellMessage]](allocShared0(sizeof(Channel[ShellMessage])))
    config = shellPanelConfig()
    client = newTriadClient()
    app = newApplication("Toasty")
    notificationStore = newNotificationStore()
    notificationDaemon = startNotificationDaemon(notificationStore)
  stopFlag[].store(false, moRelaxed)
  messageQueue[].open()
  processStopFlag = stopFlag
  setControlCHook(requestProcessStop)

  var applications = discoverApplications()
  stderr.writeLine("applications-discovered: ", applications.len)
  if notificationDaemon.error.len > 0:
    stderr.writeLine("notification-daemon-error: ", notificationDaemon.error)
  else:
    stderr.writeLine("notification-daemon: requested D-Bus name")

  let
    ui = newShellUi(
      app, config, move applications, notificationStore, client.shellCallbacks()
    )
    controller = ShellController(client: client, ui: ui, messageQueue: messageQueue)

  var initialState: TriadShellState
  var connected = false
  try:
    initialState = initTriadShellState(client.fetchSnapshot())
    connected = true
  except CatchableError as error:
    stderr.writeLine("triad-snapshot-error: ", error.msg)
  ui.updateState(move initialState, connected)
  discard app.runForFrames(1)

  let
    dispatcher = ObserverDispatcher()
    pool = newSigilThreadPool(workers = 1)
  var worker = TriadObserverWorker(
    socketPath: client.socketPath, stopFlag: stopFlag, messageQueue: messageQueue
  )
  pool.start()
  let workerProxy = worker.moveToThread(pool)
  connectThreaded(
    dispatcher, observationRequested, workerProxy, TriadObserverWorker.observeTriad()
  )
  connectThreaded(
    workerProxy,
    triadMessagesAvailable,
    controller,
    ShellController.receiveTriadMessages(),
  )
  emit dispatcher.observationRequested()

  var
    notificationRevision = notificationStore.revision
    notificationNameReported = false
  try:
    while not stopFlag[].load(moRelaxed):
      notificationDaemon.pump()
      if notificationDaemon.available and not notificationNameReported:
        stderr.writeLine("notification-daemon: ready")
        notificationNameReported = true
      if notificationStore.revision != notificationRevision:
        notificationRevision = notificationStore.revision
        ui.notificationStateChanged()
      discard app.runForFrames(1)
      sleep(8)
  finally:
    stopFlag[].store(true, moRelaxed)
    pool.stop(immediate = true)
    pool.join()
    notificationDaemon.close()
    ui.close()
    processStopFlag = nil
    messageQueue[].close()
    deallocShared(messageQueue)
    deallocShared(stopFlag)
