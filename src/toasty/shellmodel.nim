## Pure view models and navigation state for Toasty's desktop-shell surfaces.

import std/[algorithm, options, strutils]

import desktopentries
import triad/types

type
  ShellSurfaceKind* = enum
    sskNone
    sskLauncher
    sskNotifications
    sskOverview
    sskWindowSwitcher
    sskQuickSettings
    sskSession

  AppearanceMode* = enum
    amDark
    amLight

  SessionAction* = enum
    saLock
    saLogout
    saRestart
    saSuspend
    saPoweroff

  PaletteCommand* = enum
    pcNone
    pcShowNotifications
    pcShowOverview
    pcShowWindows
    pcShowQuickSettings
    pcShowSession
    pcToggleAppearance

  PaletteItemKind* = enum
    pikApplication
    pikCommand
    pikWindow

  PaletteItem* = object
    kind*: PaletteItemKind
    id*: string
    title*: string
    detail*: string
    score*: int
    applicationIndex*: int
    command*: PaletteCommand
    windowId*: uint32

  WindowItem* = object
    id*: uint32
    title*: string
    application*: string
    workspace*: string
    output*: string
    focused*: bool
    recentRank*: int

  OverviewWorkspace* = object
    workspaceIdx*: uint32
    label*: string
    active*: bool
    urgent*: bool
    windows*: seq[WindowItem]

  OverviewOutput* = object
    id*: uint32
    name*: string
    outputIndex*: int32
    logicalWidth*: int32
    logicalHeight*: int32
    scale*: float32
    primary*: bool
    workspaces*: seq[OverviewWorkspace]

  ShellNavigation* = object
    surface*: ShellSurfaceKind
    query*: string
    selectedIndex*: int
    appearance*: AppearanceMode
    pendingSessionAction*: Option[SessionAction]
    recentWindows*: seq[uint32]

func windowTitle(window: TriadWindow): string =
  if window.title.isSome and window.title.get().strip().len > 0:
    window.title.get().strip()
  elif window.appId.isSome and window.appId.get().strip().len > 0:
    window.appId.get().strip()
  else:
    "Untitled window"

func windowApplication(window: TriadWindow): string =
  if window.appId.isSome and window.appId.get().strip().len > 0:
    window.appId.get().strip()
  else:
    "Application"

func workspaceLabel(workspace: TriadWorkspace): string =
  if workspace.name.isSome and workspace.name.get().strip().len > 0:
    workspace.name.get().strip()
  else:
    $workspace.workspaceIdx

func logicalDimension(value: int32, scale: float32): int32 =
  if scale > 0.0:
    max(1, (value.float32 / scale).int32)
  else:
    max(1, value)

func searchScore*(query, title, detail: string): int =
  let
    needle = query.strip().toLowerAscii()
    primary = title.toLowerAscii()
    secondary = detail.toLowerAscii()
    combined = primary & " " & secondary
  if needle.len == 0:
    return 100
  if primary == needle:
    return 1200
  if primary.startsWith(needle):
    return 1000 - primary.len
  let primaryAt = primary.find(needle)
  if primaryAt >= 0:
    return 800 - primaryAt * 4
  let combinedAt = combined.find(needle)
  if combinedAt >= 0:
    return 650 - combinedAt * 2

  var
    needleIndex = 0
    streak = 0
    score = 0
  for character in combined:
    if needleIndex < needle.len and character == needle[needleIndex]:
      inc needleIndex
      inc streak
      score += 20 + streak * 4
    else:
      streak = 0
  if needleIndex == needle.len: score else: -1

func builtinCommands(): seq[PaletteItem] =
  @[
    PaletteItem(
      kind: pikCommand,
      id: "notifications",
      title: "Notification Center",
      detail: "View recent notifications",
      command: pcShowNotifications,
    ),
    PaletteItem(
      kind: pikCommand,
      id: "overview",
      title: "Desktop Overview",
      detail: "Browse outputs and workspaces",
      command: pcShowOverview,
    ),
    PaletteItem(
      kind: pikCommand,
      id: "windows",
      title: "Window Switcher",
      detail: "Switch to a recent window",
      command: pcShowWindows,
    ),
    PaletteItem(
      kind: pikCommand,
      id: "settings",
      title: "Quick Settings",
      detail: "Audio, network, brightness, and appearance",
      command: pcShowQuickSettings,
    ),
    PaletteItem(
      kind: pikCommand,
      id: "appearance",
      title: "Toggle Appearance",
      detail: "Switch between dark and light themes",
      command: pcToggleAppearance,
    ),
    PaletteItem(
      kind: pikCommand,
      id: "session",
      title: "Session Actions",
      detail: "Lock, logout, suspend, restart, or power off",
      command: pcShowSession,
    ),
  ]

proc paletteResults*(
    applications: openArray[DesktopApplication],
    state: TriadShellState,
    query: string,
    limit = 12,
): seq[PaletteItem] =
  for command in builtinCommands():
    var item = command
    item.score = searchScore(query, item.title, item.detail)
    if item.score >= 0:
      result.add(item)

  for index, application in applications:
    let detail = application.comment & " " & application.keywords.join(" ")
    let score = searchScore(query, application.name, detail)
    if score >= 0:
      result.add(
        PaletteItem(
          kind: pikApplication,
          id: application.id,
          title: application.name,
          detail: application.comment,
          score: score,
          applicationIndex: index,
        )
      )

  for window in state.windows:
    let
      title = window.windowTitle()
      application = window.windowApplication()
      score = searchScore(query, title, application)
    if score >= 0:
      result.add(
        PaletteItem(
          kind: pikWindow,
          id: "window-" & $window.id,
          title: title,
          detail: application,
          score: score,
          windowId: window.id,
        )
      )

  result.sort(
    proc(left, right: PaletteItem): int =
      result = cmp(right.score, left.score)
      if result == 0:
        result = cmp(left.title.toLowerAscii(), right.title.toLowerAscii())
  )
  if limit >= 0 and result.len > limit:
    result.setLen(limit)

proc noteFocusedWindow*(navigation: var ShellNavigation, state: TriadShellState) =
  var focusedId = 0'u32
  for window in state.windows:
    if window.isFocused:
      focusedId = window.id
      break
  if focusedId == 0:
    return
  let existing = navigation.recentWindows.find(focusedId)
  if existing >= 0:
    navigation.recentWindows.delete(existing)
  navigation.recentWindows.insert(focusedId, 0)
  if navigation.recentWindows.len > 64:
    navigation.recentWindows.setLen(64)

func windowSwitcherItems*(
    state: TriadShellState, recentWindows: openArray[uint32]
): seq[WindowItem] =
  for window in state.windows:
    let recentIndex = recentWindows.find(window.id)
    result.add(
      WindowItem(
        id: window.id,
        title: window.windowTitle(),
        application: window.windowApplication(),
        workspace:
          if window.workspaceIdx.isSome:
            $window.workspaceIdx.get()
          else:
            "—",
        output:
          if window.output.isSome:
            window.output.get()
          else:
            "—",
        focused: window.isFocused,
        recentRank: if recentIndex >= 0: recentIndex else: int.high,
      )
    )
  result.sort(
    proc(left, right: WindowItem): int =
      result = cmp(left.recentRank, right.recentRank)
      if result == 0:
        result = cmp(left.title.toLowerAscii(), right.title.toLowerAscii())
  )

proc overviewOutputs*(state: TriadShellState): seq[OverviewOutput] =
  var outputIndex = 0'i32
  for output in state.outputs:
    if not output.connected:
      continue
    var model = OverviewOutput(
      id: output.id,
      name: output.name,
      outputIndex: outputIndex,
      logicalWidth: logicalDimension(output.geometry.width, output.scale),
      logicalHeight: logicalDimension(output.geometry.height, output.scale),
      scale: output.scale,
      primary: output.isPrimary,
    )
    for workspace in state.workspaces:
      if workspace.output.isSome and workspace.output.get() == output.name:
        var workspaceModel = OverviewWorkspace(
          workspaceIdx: workspace.workspaceIdx,
          label: workspace.workspaceLabel(),
          active: workspace.isActive,
          urgent: workspace.isUrgent,
        )
        for window in state.windows:
          if window.workspaceIdx == some(workspace.workspaceIdx) and
              (window.output.isNone or window.output == workspace.output):
            workspaceModel.windows.add(
              WindowItem(
                id: window.id,
                title: window.windowTitle(),
                application: window.windowApplication(),
                workspace: workspaceModel.label,
                output: output.name,
                focused: window.isFocused,
              )
            )
        model.workspaces.add(workspaceModel)
    model.workspaces.sort(
      proc(left, right: OverviewWorkspace): int =
        cmp(left.workspaceIdx, right.workspaceIdx)
    )
    result.add(model)
    inc outputIndex

func sessionActionTitle*(action: SessionAction): string =
  case action
  of saLock: "Lock"
  of saLogout: "Log Out"
  of saRestart: "Restart"
  of saSuspend: "Suspend"
  of saPoweroff: "Power Off"

func sessionActionDangerous*(action: SessionAction): bool =
  action in {saLogout, saRestart, saSuspend, saPoweroff}

proc open*(navigation: var ShellNavigation, surface: ShellSurfaceKind) =
  navigation.surface = surface
  navigation.query.setLen(0)
  navigation.selectedIndex = 0
  navigation.pendingSessionAction = none(SessionAction)

proc close*(navigation: var ShellNavigation) =
  navigation.surface = sskNone
  navigation.query.setLen(0)
  navigation.selectedIndex = 0
  navigation.pendingSessionAction = none(SessionAction)

proc selectNext*(navigation: var ShellNavigation, itemCount: int) =
  if itemCount > 0:
    navigation.selectedIndex = (navigation.selectedIndex + 1) mod itemCount

proc selectPrevious*(navigation: var ShellNavigation, itemCount: int) =
  if itemCount > 0:
    navigation.selectedIndex = (navigation.selectedIndex + itemCount - 1) mod itemCount
