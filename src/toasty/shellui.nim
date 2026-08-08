## Merenda surfaces for Toasty's panel, desktop background, and shell overlays.

import std/[options, os, strutils]

import merenda/nimkit
import sigils
import sigils/selectors

import desktopentries, notifications, panelconfig, panelmodel, shellactions, shellmodel
import systemservices, triad/types

type
  ShellUiCallbacks* = object
    focusWorkspace*: proc(workspaceIdx: uint32) {.closure.}
    focusWindow*: proc(windowId: uint32) {.closure.}
    launchApplication*: proc(application: DesktopApplication) {.closure.}

  BackgroundHost = ref object
    outputId: uint32
    outputIndex: int32
    width, height: int32
    window: Window
    root: View

  PanelHost = ref object
    outputId: uint32
    outputIndex: int32
    window: Window
    root: View
    workspaceLayout: StackView
    outputLabel: Label
    titleLabel: Label
    connectionLabel: Label
    notificationButton: Button
    lastActiveWorkspace: string
    lastFocusedTitle: string
    lastConnected: bool
    hasLoggedState: bool

  OverlayHost = ref object
    kind: ShellSurfaceKind
    outputId: uint32
    window: Window
    root: View
    body: StackView
    searchField: TextField
    results: StackView

  ShellUi* = ref object of Agent
    app: Application
    config: PanelConfig
    callbacks: ShellUiCallbacks
    state: TriadShellState
    connected: bool
    applications: seq[DesktopApplication]
    notifications: NotificationStore
    navigation: ShellNavigation
    themeName: string
    settings: QuickSettingsState
    backgrounds: seq[BackgroundHost]
    panels: seq[PanelHost]
    overlay: OverlayHost
    wallpaper: ImageResource
    statusMessage: string
    lastAudibleVolume: int

proc openSurface*(ui: ShellUi, kind: ShellSurfaceKind)
proc closeOverlay(ui: ShellUi)
proc renderOverlay(ui: ShellUi)
proc updateNotificationButtons(ui: ShellUi)

func backgroundColor(mode: AppearanceMode): Color =
  case mode
  of amDark:
    color(0.018, 0.027, 0.055, 1.0)
  of amLight:
    color(0.72, 0.84, 0.94, 1.0)

func panelColor(mode: AppearanceMode): Color =
  case mode
  of amDark:
    color(0.035, 0.047, 0.075, 0.98)
  of amLight:
    color(0.91, 0.95, 0.98, 0.98)

func overlayColor(mode: AppearanceMode): Color =
  case mode
  of amDark:
    color(0.025, 0.035, 0.065, 0.98)
  of amLight:
    color(0.94, 0.97, 0.99, 0.98)

func compactText(value: string, limit = 80): string =
  result = value.replace("\n", " ").replace("\r", " ").strip()
  if result.len > limit:
    result.setLen(max(0, limit - 1))
    result.add("…")

proc removeArrangedSubviews(layout: StackView) =
  for child in layout.arrangedSubviews():
    child.removeFromSuperview()

proc shellButton(
    title, name, accessibilityLabel: string, callback: proc() {.closure.}
): Button =
  let action = actionSelector(name)
  result = newButton(title)
  result.name = name
  result.accessibilityLabel = accessibilityLabel
  result.accessibilityIdentifier = "toasty." & name
  result.action = action
  result.target = newActionTarget(action) do(sender: DynamicAgent):
    discard sender
    callback()

proc backgroundIndex(hosts: openArray[BackgroundHost], outputId: uint32): int =
  for index, host in hosts:
    if host.outputId == outputId:
      return index
  -1

proc panelIndex(hosts: openArray[PanelHost], outputId: uint32): int =
  for index, host in hosts:
    if host.outputId == outputId:
      return index
  -1

proc modelIndex(models: openArray[PanelViewModel], outputId: uint32): int =
  for index, model in models:
    if model.outputId == outputId:
      return index
  -1

proc applyAppearance(ui: ShellUi) =
  let appearance =
    if ui.themeName.len > 0:
      initAppearance(initThemeByName(ui.themeName))
    else:
      case ui.navigation.appearance
      of amDark:
        initAppearance(initDarkBSDTheme())
      of amLight:
        initAppearance(initAquaTheme())
  ui.app.setAppearance(appearance)
  for host in ui.backgrounds:
    host.root.background = backgroundColor(ui.navigation.appearance)
  for host in ui.panels:
    host.root.background = panelColor(ui.navigation.appearance)
  if not ui.overlay.isNil:
    ui.overlay.root.background = overlayColor(ui.navigation.appearance)

proc toggleAppearance(ui: ShellUi) =
  ui.navigation.appearance = if ui.navigation.appearance == amDark: amLight else: amDark
  ui.applyAppearance()
  ui.statusMessage =
    if ui.navigation.appearance == amDark: "Dark appearance" else: "Light appearance"
  if not ui.overlay.isNil:
    ui.renderOverlay()

proc createBackgroundHost(ui: ShellUi, model: PanelViewModel): BackgroundHost =
  let
    layerConfig = LayerSurfaceConfig(
      layer: lslBackground,
      anchors: {lsaTop, lsaBottom, lsaLeft, lsaRight},
      exclusiveZone: 0,
      keyboardMode: lskNone,
      output: model.outputIndex,
      namespace: "toasty-background",
    )
    window = newLayerSurfaceWindow(
      "Toasty Desktop — " & model.outputName,
      frame = rect(0, 0, model.outputWidth.float32, model.outputHeight.float32),
      config = layerConfig,
    )
    root = newView()

  root.usesThemedRootBackground = false
  root.background = backgroundColor(ui.navigation.appearance)
  root.accessibilityIgnored = true
  if not ui.wallpaper.isNil:
    let imageView = newImageView(ui.wallpaper)
    imageView.imageScaling = isScaleAxesIndependently
    imageView.imageAlignment = iaCenter
    imageView.accessibilityIgnored = true
    root.addSubview(imageView)
    discard
      imageView.pinEdges(toGuide = root.contentLayoutGuide(), edges = AllLayoutEdges)
  else:
    let
      brand = newTitleLabel("TOASTY")
      output = newStatusLabel(model.outputName & "  •  " & $model.outputScale & "×")
      branding = newStackView(laVertical)
    branding.spacing = 8.0
    branding.alignment = svaCenter
    branding.addArrangedSubview(brand, output)
    root.addSubview(branding)
    discard branding.pinEdges(
      toGuide = root.contentLayoutGuide(insets(180.0, 240.0, 180.0, 240.0)),
      edges = AllLayoutEdges,
    )

  discard ui.app.showWindow(window, root)
  stderr.writeLine(
    "background-created: output=", model.outputName, " index=", model.outputIndex,
    " scale=", model.outputScale,
  )
  BackgroundHost(
    outputId: model.outputId,
    outputIndex: model.outputIndex,
    width: model.outputWidth,
    height: model.outputHeight,
    window: window,
    root: root,
  )

proc workspaceActionTarget(
    ui: ShellUi, action: ActionSelector, workspaceIdx: uint32
): ClosureTarget =
  newActionTarget(action) do(sender: DynamicAgent):
    discard sender
    if not ui.callbacks.focusWorkspace.isNil:
      ui.callbacks.focusWorkspace(workspaceIdx)

proc createPanelHost(ui: ShellUi, model: PanelViewModel): PanelHost =
  var config = ui.config
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
    launchButton = shellButton("Apps", "launcher", "Open application launcher") do():
      ui.openSurface(sskLauncher)
    overviewButton = shellButton("Overview", "overview", "Open desktop overview") do():
      ui.openSurface(sskOverview)
    windowsButton = shellButton("Windows", "windows", "Open recent window switcher") do():
      ui.openSurface(sskWindowSwitcher)
    notificationButton = shellButton(
      "Bell", "notifications", "Open notification center"
    ) do():
      ui.openSurface(sskNotifications)
    settingsButton = shellButton("Quick", "quick-settings", "Open quick settings") do():
      ui.openSurface(sskQuickSettings)
    sessionButton = shellButton("Power", "session", "Open session actions") do():
      ui.openSurface(sskSession)

  root.usesThemedRootBackground = false
  root.background = panelColor(ui.navigation.appearance)
  root.accessibilityRole = arGroup
  root.accessibilityLabel = "Toasty desktop panel on " & model.outputName
  layout.spacing = 8.0
  layout.alignment = svaCenter
  layout.distribution = svdNatural
  workspaceLayout.spacing = 5.0
  workspaceLayout.alignment = svaCenter
  workspaceLayout.distribution = svdNatural
  outputLabel.setHuggingPriority(LayoutPriorityRequired, laHorizontal)
  connectionLabel.setHuggingPriority(LayoutPriorityRequired, laHorizontal)
  for button in [
    launchButton, overviewButton, windowsButton, notificationButton, settingsButton,
    sessionButton,
  ]:
    button.setHuggingPriority(LayoutPriorityRequired, laHorizontal)
  layout.addArrangedSubview(launchButton, outputLabel, workspaceLayout)
  layout.addFlexibleSpacer()
  layout.addArrangedSubview(
    titleLabel, overviewButton, windowsButton, notificationButton, settingsButton,
    sessionButton, connectionLabel,
  )
  root.addSubview(layout)
  layout.pinEdges(
    toGuide = root.contentLayoutGuide(insets(5.0, 10.0, 5.0, 10.0)),
    edges = {leLeft, leTop, leRight, leBottom},
  )
  discard ui.app.showWindow(window, root)
  stderr.writeLine(
    "panel-created: output=", model.outputName, " index=", model.outputIndex
  )
  PanelHost(
    outputId: model.outputId,
    outputIndex: model.outputIndex,
    window: window,
    root: root,
    workspaceLayout: workspaceLayout,
    outputLabel: outputLabel,
    titleLabel: titleLabel,
    connectionLabel: connectionLabel,
    notificationButton: notificationButton,
  )

proc updatePanelHost(ui: ShellUi, host: PanelHost, model: PanelViewModel) =
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

  host.workspaceLayout.removeArrangedSubviews()
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
    button.accessibilityLabel = "Workspace " & workspace.label
    button.accessibilityValue = if workspace.active: "active" else: "inactive"
    button.setHuggingPriority(LayoutPriorityRequired, laHorizontal)
    button.action = action
    button.target = ui.workspaceActionTarget(action, workspace.workspaceIdx)
    host.workspaceLayout.addArrangedSubview(button)

proc reconcileOutputSurfaces(ui: ShellUi) =
  let models = ui.state.panelViewModels(ui.connected)
  var index = 0
  while index < ui.backgrounds.len:
    let
      host = ui.backgrounds[index]
      desiredIndex = models.modelIndex(host.outputId)
      invalid =
        desiredIndex < 0 or models[desiredIndex].outputIndex != host.outputIndex or
        models[desiredIndex].outputWidth != host.width or
        models[desiredIndex].outputHeight != host.height
    if invalid:
      stderr.writeLine("background-removed: output_id=", host.outputId)
      host.window.close()
      ui.backgrounds.delete(index)
    else:
      inc index

  index = 0
  while index < ui.panels.len:
    let
      host = ui.panels[index]
      desiredIndex = models.modelIndex(host.outputId)
    if desiredIndex < 0 or models[desiredIndex].outputIndex != host.outputIndex:
      stderr.writeLine("panel-removed: output_id=", host.outputId)
      host.window.close()
      ui.panels.delete(index)
    else:
      inc index

  for model in models:
    if ui.backgrounds.backgroundIndex(model.outputId) < 0:
      ui.backgrounds.add(ui.createBackgroundHost(model))
    var panelIndex = ui.panels.panelIndex(model.outputId)
    if panelIndex < 0:
      ui.panels.add(ui.createPanelHost(model))
      panelIndex = ui.panels.high
    ui.updatePanelHost(ui.panels[panelIndex], model)
  ui.updateNotificationButtons()

proc activeOutput(ui: ShellUi): OverviewOutput =
  let outputs = ui.state.overviewOutputs()
  if outputs.len == 0:
    return
  var activeOutputName = ""
  for workspace in ui.state.workspaces:
    if workspace.isActive and workspace.output.isSome:
      activeOutputName = workspace.output.get()
      break
  for output in outputs:
    if output.name == activeOutputName:
      return output
  for output in outputs:
    if output.primary:
      return output
  outputs[0]

func surfaceTitle(kind: ShellSurfaceKind): string =
  case kind
  of sskNone: "Toasty"
  of sskLauncher: "Applications and Commands"
  of sskNotifications: "Notification Center"
  of sskOverview: "Desktop Overview"
  of sskWindowSwitcher: "Recent Windows"
  of sskQuickSettings: "Quick Settings"
  of sskSession: "Session Actions"

proc createOverlay(ui: ShellUi, kind: ShellSurfaceKind): OverlayHost =
  let
    output = ui.activeOutput()
    topMargin = ui.config.height + ui.config.margin
    layerConfig = LayerSurfaceConfig(
      layer: lslOverlay,
      anchors: {lsaTop, lsaBottom, lsaLeft, lsaRight},
      margins: LayerSurfaceMargins(top: topMargin),
      exclusiveZone: 0,
      keyboardMode: lskExclusive,
      output: output.outputIndex,
      namespace: "toasty-shell-overlay",
    )
    window = newLayerSurfaceWindow(
      "Toasty — " & kind.surfaceTitle(),
      frame = rect(
        0,
        0,
        max(output.logicalWidth, 640).float32,
        max(output.logicalHeight - topMargin, 480).float32,
      ),
      config = layerConfig,
      transparent = true,
    )
    root = newView()
    layout = newStackView(laVertical)
    header = newStackView(laHorizontal)
    title = newTitleLabel(kind.surfaceTitle())
    body = newStackView(laVertical)
    closeButton = shellButton("Close", "close-overlay", "Close shell overlay") do():
      ui.closeOverlay()

  root.usesThemedRootBackground = false
  root.background = overlayColor(ui.navigation.appearance)
  root.accessibilityRole = arGroup
  root.accessibilityLabel = kind.surfaceTitle()
  layout.spacing = 16.0
  layout.alignment = svaFill
  header.spacing = 12.0
  header.alignment = svaCenter
  header.addArrangedSubview(title)
  header.addFlexibleSpacer()
  header.addArrangedSubview(closeButton)
  body.spacing = 10.0
  body.alignment = svaFill
  layout.addArrangedSubview(header, body)
  root.addSubview(layout)
  layout.pinEdges(
    toGuide = root.contentLayoutGuide(insets(32.0, 64.0, 32.0, 64.0)),
    edges = AllLayoutEdges,
  )
  OverlayHost(kind: kind, outputId: output.id, window: window, root: root, body: body)

proc activatePaletteItem(ui: ShellUi, item: PaletteItem) =
  case item.kind
  of pikApplication:
    if item.applicationIndex in 0 ..< ui.applications.len and
        not ui.callbacks.launchApplication.isNil:
      ui.callbacks.launchApplication(ui.applications[item.applicationIndex])
      ui.closeOverlay()
  of pikWindow:
    if not ui.callbacks.focusWindow.isNil:
      ui.callbacks.focusWindow(item.windowId)
      ui.closeOverlay()
  of pikCommand:
    case item.command
    of pcNone:
      discard
    of pcShowNotifications:
      ui.openSurface(sskNotifications)
    of pcShowOverview:
      ui.openSurface(sskOverview)
    of pcShowWindows:
      ui.openSurface(sskWindowSwitcher)
    of pcShowQuickSettings:
      ui.openSurface(sskQuickSettings)
    of pcShowSession:
      ui.openSurface(sskSession)
    of pcToggleAppearance:
      ui.toggleAppearance()

proc paletteResultButton(ui: ShellUi, item: PaletteItem): Button =
  let
    selectedItem = item
    label =
      if selectedItem.detail.len > 0:
        selectedItem.title & " — " & selectedItem.detail.compactText(64)
      else:
        selectedItem.title
  result = shellButton(label, "palette-" & selectedItem.id, selectedItem.title) do():
    ui.activatePaletteItem(selectedItem)
  result.setHuggingPriority(LayoutPriorityLow, laHorizontal)

proc renderPaletteResults(ui: ShellUi) =
  if ui.overlay.isNil or ui.overlay.results.isNil:
    return
  ui.overlay.results.removeArrangedSubviews()
  let results = ui.applications.paletteResults(ui.state, ui.navigation.query)
  if results.len == 0:
    ui.overlay.results.addArrangedSubview(newStatusLabel("No matching result"))
  for item in results:
    ui.overlay.results.addArrangedSubview(ui.paletteResultButton(item))

proc paletteChanged(ui: ShellUi, sender: DynamicAgent) {.slot.} =
  discard sender
  if not ui.overlay.isNil and not ui.overlay.searchField.isNil:
    ui.navigation.query = ui.overlay.searchField.stringValue
    ui.renderPaletteResults()

proc renderLauncher(ui: ShellUi) =
  let overlay = ui.overlay
  if overlay.searchField.isNil:
    overlay.searchField = newTextField(ui.navigation.query)
    overlay.searchField.name = "palette-search"
    overlay.searchField.accessibilityLabel = "Search applications and commands"
    overlay.searchField.accessibilityHelp =
      "Type to filter; press Tab to move through results and Enter to activate"
    overlay.results = newStackView(laVertical)
    overlay.results.spacing = 7.0
    overlay.results.alignment = svaFill
    let action = actionSelector("activateFirstPaletteResult")
    overlay.searchField.action = action
    overlay.searchField.target = newActionTarget(action) do(sender: DynamicAgent):
      discard sender
      let results = ui.applications.paletteResults(ui.state, ui.navigation.query)
      if results.len > 0:
        ui.activatePaletteItem(results[0])
    overlay.searchField.connect(textDidChange, ui, paletteChanged)
    overlay.body.addArrangedSubview(overlay.searchField, overlay.results)
  ui.renderPaletteResults()

proc focusWindowButton(ui: ShellUi, window: WindowItem): Button =
  let
    marker = if window.focused: "● " else: ""
    windowId = window.id
  shellButton(
    marker & window.title & " — " & window.application,
    "focus-window-" & $window.id,
    "Focus " & window.title,
  ) do():
    if not ui.callbacks.focusWindow.isNil:
      ui.callbacks.focusWindow(windowId)
    ui.closeOverlay()

proc renderOverview(ui: ShellUi) =
  ui.overlay.body.removeArrangedSubviews()
  let outputs = ui.state.overviewOutputs()
  if outputs.len == 0:
    ui.overlay.body.addArrangedSubview(newStatusLabel("No connected outputs"))
  for output in outputs:
    let outputTitle = newHeadingLabel(
      output.name & "  " & $output.logicalWidth & "×" & $output.logicalHeight &
        "  scale " & $output.scale
    )
    outputTitle.accessibilityLabel = "Output " & output.name
    ui.overlay.body.addArrangedSubview(outputTitle)
    for workspace in output.workspaces:
      let
        workspaceIdx = workspace.workspaceIdx
        row = newStackView(laHorizontal)
        marker = if workspace.active: "● " else: ""
        workspaceButton = shellButton(
          marker & workspace.label,
          "overview-workspace-" & $workspace.workspaceIdx,
          "Focus workspace " & workspace.label,
        ) do():
          if not ui.callbacks.focusWorkspace.isNil:
            ui.callbacks.focusWorkspace(workspaceIdx)
          ui.closeOverlay()
      row.spacing = 8.0
      row.alignment = svaCenter
      workspaceButton.setHuggingPriority(LayoutPriorityRequired, laHorizontal)
      row.addArrangedSubview(workspaceButton)
      for window in workspace.windows:
        row.addArrangedSubview(ui.focusWindowButton(window))
      if workspace.windows.len == 0:
        row.addArrangedSubview(newStatusLabel("Empty"))
      ui.overlay.body.addArrangedSubview(row)

proc renderWindowSwitcher(ui: ShellUi) =
  ui.overlay.body.removeArrangedSubviews()
  let windows = ui.state.windowSwitcherItems(ui.navigation.recentWindows)
  if windows.len == 0:
    ui.overlay.body.addArrangedSubview(newStatusLabel("No managed windows"))
  for window in windows:
    ui.overlay.body.addArrangedSubview(ui.focusWindowButton(window))

proc dismissNotification(ui: ShellUi, id: uint32) =
  discard ui.notifications.close(id)
  ui.updateNotificationButtons()
  ui.renderOverlay()

proc renderNotifications(ui: ShellUi) =
  ui.overlay.body.removeArrangedSubviews()
  let clearButton = shellButton(
    "Clear All", "clear-notifications", "Clear all notifications"
  ) do():
    ui.notifications.clear()
    ui.updateNotificationButtons()
    ui.renderOverlay()
  clearButton.enabled = ui.notifications.items.len > 0
  ui.overlay.body.addArrangedSubview(clearButton)
  if ui.notifications.items.len == 0:
    ui.overlay.body.addArrangedSubview(newStatusLabel("No notifications"))
  for notification in ui.notifications.items:
    let
      notificationId = notification.id
      row = newStackView(laHorizontal)
      content = newStackView(laVertical)
      source = newStatusLabel(notification.application.compactText(48))
      summary = newHeadingLabel(notification.summary.compactText(80))
      body = newLabel(notification.body.compactText(120))
      dismiss = shellButton(
        "Dismiss",
        "dismiss-notification-" & $notification.id,
        "Dismiss " & notification.summary,
      ) do():
        ui.dismissNotification(notificationId)
    row.spacing = 12.0
    row.alignment = svaCenter
    content.spacing = 3.0
    content.alignment = svaFill
    content.addArrangedSubview(source, summary)
    if notification.body.len > 0:
      content.addArrangedSubview(body)
    row.addArrangedSubview(content, dismiss)
    ui.overlay.body.addArrangedSubview(row)

proc refreshSettings(ui: ShellUi) =
  ui.settings = probeQuickSettings()
  if ui.settings.volume > 0:
    ui.lastAudibleVolume = ui.settings.volume

proc adjustVolume(ui: ShellUi, delta: int) =
  let target = clamp(ui.settings.volume + delta, 0, 100)
  let runner: CommandRunner = systemCommandRunner
  let result = runner.setVolume(target)
  ui.statusMessage =
    if result.exitCode == 0:
      "Volume " & $target & "%"
    else:
      result.output.compactText()
  ui.refreshSettings()
  ui.renderOverlay()

proc toggleMute(ui: ShellUi) =
  let target =
    if ui.settings.volume > 0:
      ui.lastAudibleVolume = ui.settings.volume
      0
    else:
      max(ui.lastAudibleVolume, 50)
  ui.adjustVolume(target - ui.settings.volume)

proc adjustBrightness(ui: ShellUi, delta: int) =
  if ui.settings.brightness.isNone:
    return
  let
    target = clamp(ui.settings.brightness.get() + delta, 0, 100)
    runner: CommandRunner = systemCommandRunner
    result = runner.setBrightness(target)
  ui.statusMessage =
    if result.exitCode == 0:
      "Brightness " & $target & "%"
    else:
      result.output.compactText()
  ui.refreshSettings()
  ui.renderOverlay()

proc renderQuickSettings(ui: ShellUi) =
  ui.overlay.body.removeArrangedSubviews()
  let
    audio = newStackView(laHorizontal)
    audioStatus =
      if ui.settings.audioAvailable:
        "Volume " & $ui.settings.volume & "%"
      else:
        "Audio unavailable"
    audioLabel = newHeadingLabel(audioStatus)
    volumeDown = shellButton("−", "volume-down", "Decrease volume") do():
      ui.adjustVolume(-5)
    mute = shellButton("Mute", "volume-mute", "Toggle audio mute") do():
      ui.toggleMute()
    volumeUp = shellButton("+", "volume-up", "Increase volume") do():
      ui.adjustVolume(5)
  audio.spacing = 8.0
  audio.alignment = svaCenter
  audio.addArrangedSubview(audioLabel)
  audio.addFlexibleSpacer()
  audio.addArrangedSubview(volumeDown, mute, volumeUp)
  for button in [volumeDown, mute, volumeUp]:
    button.enabled = ui.settings.audioAvailable
  ui.overlay.body.addArrangedSubview(audio)

  let
    network = newStackView(laHorizontal)
    networkLabel = newHeadingLabel(
      if ui.settings.networkConnected:
        "Network  " & ui.settings.networkInterface
      else:
        "Network disconnected"
    )
    refresh = shellButton("Refresh", "network-refresh", "Refresh network status") do():
      ui.refreshSettings()
      ui.statusMessage = "Network status refreshed"
      ui.renderOverlay()
  network.spacing = 8.0
  network.alignment = svaCenter
  network.addArrangedSubview(networkLabel)
  network.addFlexibleSpacer()
  network.addArrangedSubview(refresh)
  ui.overlay.body.addArrangedSubview(network)

  let brightness = newStackView(laHorizontal)
  brightness.spacing = 8.0
  brightness.alignment = svaCenter
  if ui.settings.brightness.isSome:
    let
      label = newHeadingLabel("Brightness " & $ui.settings.brightness.get() & "%")
      down = shellButton("−", "brightness-down", "Decrease brightness") do():
        ui.adjustBrightness(-5)
      up = shellButton("+", "brightness-up", "Increase brightness") do():
        ui.adjustBrightness(5)
    brightness.addArrangedSubview(label)
    brightness.addFlexibleSpacer()
    brightness.addArrangedSubview(down, up)
  else:
    brightness.addArrangedSubview(newHeadingLabel("Brightness unavailable"))
  ui.overlay.body.addArrangedSubview(brightness)

  let
    appearance = newStackView(laHorizontal)
    appearanceLabel = newHeadingLabel(
      if ui.navigation.appearance == amDark: "Appearance  Dark" else: "Appearance  Light"
    )
    toggle = shellButton(
      "Toggle", "appearance-toggle", "Toggle light and dark appearance"
    ) do():
      ui.toggleAppearance()
  appearance.spacing = 8.0
  appearance.alignment = svaCenter
  appearance.addArrangedSubview(appearanceLabel)
  appearance.addFlexibleSpacer()
  appearance.addArrangedSubview(toggle)
  ui.overlay.body.addArrangedSubview(appearance)
  if ui.statusMessage.len > 0:
    ui.overlay.body.addArrangedSubview(newStatusLabel(ui.statusMessage))

proc requestSessionAction(ui: ShellUi, action: SessionAction) =
  if action.sessionActionDangerous():
    ui.navigation.pendingSessionAction = some(action)
    ui.renderOverlay()
  else:
    ui.statusMessage = action.performSessionAction()
    ui.renderOverlay()

proc renderSession(ui: ShellUi) =
  ui.overlay.body.removeArrangedSubviews()
  if ui.navigation.pendingSessionAction.isSome:
    let
      action = ui.navigation.pendingSessionAction.get()
      warning = newHeadingLabel("Confirm " & action.sessionActionTitle() & "?")
      row = newStackView(laHorizontal)
      confirm = shellButton(
        "Confirm", "confirm-session-action", "Confirm " & action.sessionActionTitle()
      ) do():
        ui.statusMessage = action.performSessionAction()
        ui.navigation.pendingSessionAction = none(SessionAction)
        ui.renderOverlay()
      cancel = shellButton("Cancel", "cancel-session-action", "Cancel session action") do():
        ui.navigation.pendingSessionAction = none(SessionAction)
        ui.renderOverlay()
    row.spacing = 12.0
    row.alignment = svaCenter
    row.addArrangedSubview(confirm, cancel)
    ui.overlay.body.addArrangedSubview(warning, row)
  else:
    for action in SessionAction:
      let requestedAction = action
      let button = shellButton(
        requestedAction.sessionActionTitle(),
        "session-" & ($requestedAction).toLowerAscii(),
        requestedAction.sessionActionTitle(),
      ) do():
        ui.requestSessionAction(requestedAction)
      button.enabled = requestedAction.sessionActionAvailable()
      ui.overlay.body.addArrangedSubview(button)
  if ui.statusMessage.len > 0:
    ui.overlay.body.addArrangedSubview(newStatusLabel(ui.statusMessage))

proc renderOverlay(ui: ShellUi) =
  if ui.overlay.isNil:
    return
  case ui.overlay.kind
  of sskNone:
    discard
  of sskLauncher:
    ui.renderLauncher()
  of sskNotifications:
    ui.renderNotifications()
  of sskOverview:
    ui.renderOverview()
  of sskWindowSwitcher:
    ui.renderWindowSwitcher()
  of sskQuickSettings:
    ui.renderQuickSettings()
  of sskSession:
    ui.renderSession()

proc closeOverlay(ui: ShellUi) =
  if not ui.overlay.isNil:
    ui.overlay.window.close()
    ui.overlay = nil
  ui.navigation.close()

proc openSurface*(ui: ShellUi, kind: ShellSurfaceKind) =
  if kind == sskNone:
    ui.closeOverlay()
    return
  ui.closeOverlay()
  ui.navigation.open(kind)
  ui.statusMessage.setLen(0)
  if kind == sskNotifications:
    ui.notifications.markAllRead()
    ui.updateNotificationButtons()
  elif kind == sskQuickSettings:
    ui.refreshSettings()
  ui.overlay = ui.createOverlay(kind)
  ui.renderOverlay()
  discard ui.app.showWindow(
    ui.overlay.window,
    ui.overlay.root,
    if ui.overlay.searchField.isNil:
      nil
    else:
      Responder(ui.overlay.searchField),
  )
  stderr.writeLine("shell-overlay: opened ", kind.surfaceTitle())

proc updateNotificationButtons(ui: ShellUi) =
  let unread = ui.notifications.unreadCount()
  for host in ui.panels:
    host.notificationButton.title =
      if unread > 0:
        "Bell " & $unread
      else:
        "Bell"
    host.notificationButton.accessibilityValue = $unread & " unread"

proc updateState*(ui: ShellUi, state: sink TriadShellState, connected: bool) =
  ui.state = move state
  ui.connected = connected
  ui.navigation.noteFocusedWindow(ui.state)
  ui.reconcileOutputSurfaces()
  if not ui.overlay.isNil:
    case ui.overlay.kind
    of sskLauncher:
      ui.renderPaletteResults()
    of sskOverview, sskWindowSwitcher:
      ui.renderOverlay()
    else:
      discard

proc applyEvent*(ui: ShellUi, event: TriadEvent) =
  ui.state.apply(event)
  ui.navigation.noteFocusedWindow(ui.state)
  ui.reconcileOutputSurfaces()
  if not ui.overlay.isNil:
    case ui.overlay.kind
    of sskLauncher:
      ui.renderPaletteResults()
    of sskOverview, sskWindowSwitcher:
      ui.renderOverlay()
    else:
      discard

proc setConnected*(ui: ShellUi, connected: bool) =
  if ui.connected != connected:
    ui.connected = connected
    ui.reconcileOutputSurfaces()

proc notificationStateChanged*(ui: ShellUi) =
  ui.updateNotificationButtons()
  if not ui.overlay.isNil and ui.overlay.kind == sskNotifications:
    ui.renderNotifications()

proc close*(ui: ShellUi) =
  ui.closeOverlay()
  for host in ui.panels:
    host.window.close()
  for host in ui.backgrounds:
    host.window.close()
  ui.panels.setLen(0)
  ui.backgrounds.setLen(0)

proc newShellUi*(
    app: Application,
    config: PanelConfig,
    applications: sink seq[DesktopApplication],
    notifications: NotificationStore,
    callbacks: sink ShellUiCallbacks,
): ShellUi =
  result = ShellUi(
    app: app,
    config: config,
    applications: move applications,
    notifications: notifications,
    callbacks: move callbacks,
    themeName: themeNameFromEnv(),
    lastAudibleVolume: 50,
  )
  if result.themeName.len > 0:
    stderr.writeLine("shell-theme: ", result.themeName)
  let wallpaperPath = getEnv("TOASTY_WALLPAPER")
  if wallpaperPath.len > 0 and fileExists(wallpaperPath):
    try:
      result.wallpaper = newImageResourceFromFile(wallpaperPath, "toasty-wallpaper")
      stderr.writeLine("wallpaper: ", wallpaperPath)
    except CatchableError as error:
      stderr.writeLine("wallpaper-error: ", error.msg)
  result.applyAppearance()
