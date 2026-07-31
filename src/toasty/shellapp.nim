import std/[atomics, os, strutils]

import merenda/nimkit
import sigils
import sigils/selectors

import panelconfig, panelmodel, triad

const
  ObserverReceiveTimeoutMs = 100
  ObserverReconnectDelayMs = 250

type
  PanelMessageKind = enum
    pmEvent
    pmSnapshot
    pmConnection

  PanelMessage = object
    case kind: PanelMessageKind
    of pmEvent:
      event: TriadEvent
    of pmSnapshot:
      snapshot: TriadSnapshot
    of pmConnection:
      connected: bool

  PanelHost = ref object
    outputId: uint32
    outputIndex: int32
    window: Window
    workspaceLayout: StackView
    outputLabel: Label
    titleLabel: Label
    connectionLabel: Label
    lastActiveWorkspace: string
    lastFocusedTitle: string
    lastConnected: bool
    hasLoggedState: bool

  PanelController = ref object of Agent
    app: Application
    client: TriadClient
    config: PanelConfig
    state: TriadShellState
    connected: bool
    hosts: seq[PanelHost]
    messageQueue: ptr Channel[PanelMessage]

  ObserverDispatcher = ref object of Agent

  TriadObserverWorker = ref object of AgentActor
    socketPath: string
    stopFlag: ptr Atomic[bool]
    messageQueue: ptr Channel[PanelMessage]

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
      stderr.writeLine("panel-font: ", path)
      return

proc modelIndex(models: openArray[PanelViewModel], outputId: uint32): int =
  for index, model in models:
    if model.outputId == outputId:
      return index
  -1

proc hostIndex(hosts: openArray[PanelHost], outputId: uint32): int =
  for index, host in hosts:
    if host.outputId == outputId:
      return index
  -1

proc workspaceActionTarget(
    client: TriadClient,
    action: ActionSelector,
    outputName: string,
    workspaceIdx: uint32,
): ClosureTarget =
  newActionTarget(action) do(sender: DynamicAgent):
    discard sender
    try:
      client.focusWorkspace(workspaceIdx)
      stderr.writeLine(
        "workspace-click: output=", outputName, " workspace=", workspaceIdx
      )
    except CatchableError as error:
      stderr.writeLine("workspace-click-error: ", error.msg)

proc createPanelHost(controller: PanelController, model: PanelViewModel): PanelHost =
  var config = controller.config
  config.output = model.outputIndex
  let
    anchors =
      if config.edge == peTop:
        {lsaTop, lsaLeft, lsaRight}
      else:
        {lsaBottom, lsaLeft, lsaRight}
    layerConfig = LayerSurfaceConfig(
      layer: lslTop,
      anchors: anchors,
      margins: LayerSurfaceMargins(
        top: config.margin,
        right: config.margin,
        bottom: config.margin,
        left: config.margin,
      ),
      exclusiveZone: config.height + config.margin,
      keyboardMode: lskNone,
      output: config.output,
      namespace: config.namespace,
    )
    window = newLayerSurfaceWindow(
      "Toasty Panel — " & model.outputName,
      frame = rect(0, 0, max(model.outputWidth, 320).float32, config.height.float32),
      config = layerConfig,
    )
    root = newView()
    layout = newStackView(laHorizontal)
    outputLabel = newStatusLabel(model.outputName)
    workspaceLayout = newStackView(laHorizontal)
    titleLabel = newLabel(model.focusedTitle)
    connectionLabel = newStatusLabel("+")

  root.usesThemedRootBackground = false
  root.background = color(0.035, 0.047, 0.075, 0.98)
  layout.spacing = 12.0
  layout.alignment = svaCenter
  layout.distribution = svdNatural
  workspaceLayout.spacing = 6.0
  workspaceLayout.alignment = svaCenter
  workspaceLayout.distribution = svdNatural
  outputLabel.setHuggingPriority(LayoutPriorityRequired, laHorizontal)
  connectionLabel.setHuggingPriority(LayoutPriorityRequired, laHorizontal)
  layout.addArrangedSubview(outputLabel, workspaceLayout)
  layout.addFlexibleSpacer()
  layout.addArrangedSubview(titleLabel, connectionLabel)
  root.addSubview(layout)
  layout.pinEdges(
    toGuide = root.contentLayoutGuide(insets(6.0, 12.0, 6.0, 12.0)),
    edges = {leLeft, leTop, leRight, leBottom},
  )
  discard controller.app.showWindow(window, root)
  stderr.writeLine(
    "panel-created: output=", model.outputName, " index=", model.outputIndex
  )
  PanelHost(
    outputId: model.outputId,
    outputIndex: model.outputIndex,
    window: window,
    workspaceLayout: workspaceLayout,
    outputLabel: outputLabel,
    titleLabel: titleLabel,
    connectionLabel: connectionLabel,
  )

proc updatePanelHost(
    controller: PanelController, host: PanelHost, model: PanelViewModel
) =
  host.outputLabel.text = model.outputName
  host.titleLabel.text = model.focusedTitle
  host.connectionLabel.text = if model.connected: "+" else: "-"

  var activeWorkspace = "none"
  for workspace in model.workspaces:
    if workspace.active:
      activeWorkspace = workspace.label
      break
  if not host.hasLoggedState or host.lastActiveWorkspace != activeWorkspace or
      host.lastFocusedTitle != model.focusedTitle or
      host.lastConnected != model.connected:
    stderr.writeLine(
      "panel-state: output=", model.outputName, " workspace=", activeWorkspace,
      " title=", model.focusedTitle, " connected=", model.connected,
    )
    host.lastActiveWorkspace = activeWorkspace
    host.lastFocusedTitle = model.focusedTitle
    host.lastConnected = model.connected
    host.hasLoggedState = true

  for child in host.workspaceLayout.arrangedSubviews():
    child.removeFromSuperview()

  for workspace in model.workspaces:
    var marker = if workspace.active: "> " else: ""
    if workspace.urgent:
      marker.add("! ")
    elif workspace.occupied:
      marker.add("* ")
    let
      button = newButton(marker & workspace.label)
      action = actionSelector("focusWorkspace")
    button.name = "workspace-" & $workspace.workspaceIdx
    button.state = if workspace.active: bsOn else: bsOff
    button.setHuggingPriority(LayoutPriorityRequired, laHorizontal)
    button.action = action
    button.target = workspaceActionTarget(
      controller.client, action, model.outputName, workspace.workspaceIdx
    )
    host.workspaceLayout.addArrangedSubview(button)

proc reconcilePanels(controller: PanelController) =
  let models = controller.state.panelViewModels(controller.connected)
  var index = 0
  while index < controller.hosts.len:
    let
      host = controller.hosts[index]
      desiredIndex = models.modelIndex(host.outputId)
    if desiredIndex < 0 or models[desiredIndex].outputIndex != host.outputIndex:
      stderr.writeLine("panel-removed: output_id=", host.outputId)
      host.window.close()
      controller.hosts.delete(index)
    else:
      inc index

  for model in models:
    var index = controller.hosts.hostIndex(model.outputId)
    if index < 0:
      controller.hosts.add(controller.createPanelHost(model))
      index = controller.hosts.high
    controller.updatePanelHost(controller.hosts[index], model)

proc receiveTriadMessages(controller: PanelController) {.slot.} =
  while true:
    var received = controller.messageQueue[].tryRecv()
    if not received.dataAvailable:
      break
    case received.msg.kind
    of pmEvent:
      controller.state.apply(received.msg.event)
      controller.reconcilePanels()
    of pmSnapshot:
      controller.state.apply(
        TriadEvent(kind: tekStateChanged, snapshot: received.msg.snapshot)
      )
      controller.reconcilePanels()
    of pmConnection:
      controller.connected = received.msg.connected
      controller.reconcilePanels()
      stderr.writeLine(
        "triad-subscription: ",
        (if received.msg.connected: "connected" else: "disconnected"),
      )

proc observeTriad(worker: TriadObserverWorker) {.slot.} =
  let client = newTriadClient(worker.socketPath)
  let onEvent: TriadEventCallback = proc(event: sink TriadEvent) =
    worker.messageQueue[].send(PanelMessage(kind: pmEvent, event: move event))
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
          PanelMessage(kind: pmSnapshot, snapshot: move snapshot)
        )
      except CatchableError as snapshotError:
        stderr.writeLine("triad-snapshot-error: ", snapshotError.msg)
    elif error.len > 0:
      stderr.writeLine("triad-subscription-error: ", error)
    worker.messageQueue[].send(PanelMessage(kind: pmConnection, connected: connected))
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
      cast[ptr Channel[PanelMessage]](allocShared0(sizeof(Channel[PanelMessage])))
    config = shellPanelConfig()
    client = newTriadClient()
    app = newApplication("Toasty")
  stopFlag[].store(false, moRelaxed)
  messageQueue[].open()
  processStopFlag = stopFlag
  setControlCHook(requestProcessStop)
  app.setAppearance(initAppearance(initDarkBSDTheme()))

  var state: TriadShellState
  var connected = false
  try:
    state = initTriadShellState(client.fetchSnapshot())
    connected = true
  except CatchableError as error:
    stderr.writeLine("triad-snapshot-error: ", error.msg)

  let controller = PanelController(
    app: app,
    client: client,
    config: config,
    state: state,
    connected: connected,
    messageQueue: messageQueue,
  )
  controller.reconcilePanels()
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
    PanelController.receiveTriadMessages(),
  )
  emit dispatcher.observationRequested()

  try:
    while not stopFlag[].load(moRelaxed):
      discard app.runForFrames(1)
      sleep(8)
  finally:
    stopFlag[].store(true, moRelaxed)
    pool.stop(immediate = true)
    pool.join()
    for host in controller.hosts:
      host.window.close()
    processStopFlag = nil
    messageQueue[].close()
    deallocShared(messageQueue)
    deallocShared(stopFlag)
