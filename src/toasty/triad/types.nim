import std/options

const TriadIpcVersion* = 1'u32

type
  TriadProtocolError* = object of CatchableError

  TriadGeometry* = object
    x*: int32
    y*: int32
    width*: int32
    height*: int32

  TriadSize* = object
    width*: int32
    height*: int32

  TriadOutput* = object
    id*: uint32
    name*: string
    connected*: bool
    isPrimary*: bool
    refreshRate*: int32
    physicalWidth*: int32
    physicalHeight*: int32
    scale*: float32
    transform*: string
    geometry*: TriadGeometry

  TriadWorkspace* = object
    tagId*: uint32
    workspaceIdx*: uint32
    name*: Option[string]
    output*: Option[string]
    layout*: string
    layoutKind*: string
    runtimeKind*: string
    layoutSource*: string
    fallbackLayout*: string
    isConfigured*: bool
    isActive*: bool
    isOutputVisible*: bool
    isUrgent*: bool
    occupied*: bool
    focusedWindowId*: Option[uint32]

  TriadWindowPosition* = object
    columnIdx*: Option[uint32]
    windowIdx*: Option[uint32]

  TriadWindow* = object
    id*: uint32
    pid*: Option[int32]
    parentId*: Option[uint32]
    title*: Option[string]
    appId*: Option[string]
    tagId*: Option[uint32]
    workspaceIdx*: Option[uint32]
    output*: Option[string]
    position*: TriadWindowPosition
    isFocused*: bool
    isFloating*: bool
    isMaximized*: bool
    isMinimized*: bool
    isSticky*: bool
    isOverlay*: bool
    isUnmanagedGlobal*: bool
    isFullscreen*: bool
    fullscreenOutput*: Option[uint32]
    widthProportion*: float32
    heightProportion*: float32
    actualSize*: TriadSize
    floatingGeometry*: TriadGeometry
    keyboardShortcutsInhibit*: bool
    idleInhibit*: string
    isTerminal*: bool
    allowSwallow*: bool
    swallowedBy*: Option[uint32]
    swallowing*: Option[uint32]

  TriadSnapshot* = object
    version*: uint32
    activeTag*: uint32
    activeWorkspaceIdx*: uint32
    outputs*: seq[TriadOutput]
    workspaces*: seq[TriadWorkspace]
    windows*: seq[TriadWindow]

  TriadEventScope* = enum
    tesLayout
    tesState
    tesWindow
    tesCapture

  TriadEventKind* = enum
    tekLayoutStateChanged
    tekStateChanged
    tekWindowChanged
    tekCaptureSessionsChanged

  TriadEvent* = object
    kind*: TriadEventKind
    activeTag*: uint32
    activeWorkspaceIdx*: uint32
    workspaces*: seq[TriadWorkspace]
    snapshot*: TriadSnapshot
    window*: Option[TriadWindow]

  TriadShellState* = object
    version*: uint32
    activeTag*: uint32
    activeWorkspaceIdx*: uint32
    outputs*: seq[TriadOutput]
    workspaces*: seq[TriadWorkspace]
    windows*: seq[TriadWindow]

proc initTriadShellState*(snapshot: TriadSnapshot): TriadShellState =
  TriadShellState(
    version: snapshot.version,
    activeTag: snapshot.activeTag,
    activeWorkspaceIdx: snapshot.activeWorkspaceIdx,
    outputs: snapshot.outputs,
    workspaces: snapshot.workspaces,
    windows: snapshot.windows,
  )

proc apply*(state: var TriadShellState, event: TriadEvent) =
  case event.kind
  of tekLayoutStateChanged:
    state.activeTag = event.activeTag
    state.activeWorkspaceIdx = event.activeWorkspaceIdx
    state.workspaces = event.workspaces
  of tekStateChanged:
    state = initTriadShellState(event.snapshot)
  of tekWindowChanged:
    if event.window.isNone:
      return
    let updated = event.window.get()
    for index, window in state.windows:
      if window.id == updated.id:
        state.windows[index] = updated
        return
    state.windows.add(updated)
  of tekCaptureSessionsChanged:
    discard
