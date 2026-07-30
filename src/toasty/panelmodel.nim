import std/[algorithm, options, strutils]

import triad/types

type
  WorkspaceItem* = object
    workspaceIdx*: uint32
    label*: string
    active*: bool
    urgent*: bool
    occupied*: bool

  PanelViewModel* = object
    outputId*: uint32
    outputName*: string
    outputIndex*: int32
    outputWidth*: int32
    connected*: bool
    workspaces*: seq[WorkspaceItem]
    focusedTitle*: string

proc workspaceLabel(workspace: TriadWorkspace): string =
  if workspace.name.isSome and workspace.name.get().strip().len > 0:
    workspace.name.get().strip()
  else:
    $workspace.workspaceIdx

proc focusedTitle(state: TriadShellState): string =
  for window in state.windows:
    if not window.isFocused:
      continue
    if window.title.isSome and window.title.get().strip().len > 0:
      return window.title.get().strip()
    if window.appId.isSome and window.appId.get().strip().len > 0:
      return window.appId.get().strip()
  "Desktop"

proc panelViewModels*(state: TriadShellState, connected = true): seq[PanelViewModel] =
  let title = state.focusedTitle()
  var outputIndex = 0'i32
  for output in state.outputs:
    if not output.connected:
      continue
    var model = PanelViewModel(
      outputId: output.id,
      outputName: output.name,
      outputIndex: outputIndex,
      outputWidth: output.geometry.width,
      connected: connected,
      focusedTitle: title,
    )
    for workspace in state.workspaces:
      if workspace.output.isSome and workspace.output.get() == output.name:
        model.workspaces.add(
          WorkspaceItem(
            workspaceIdx: workspace.workspaceIdx,
            label: workspace.workspaceLabel(),
            active: workspace.isActive,
            urgent: workspace.isUrgent,
            occupied: workspace.occupied,
          )
        )
    model.workspaces.sort(
      proc(left, right: WorkspaceItem): int =
        cmp(left.workspaceIdx, right.workspaceIdx)
    )
    result.add(model)
    inc outputIndex
