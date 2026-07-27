## Backend-independent configuration for Toasty's desktop panel.

type
  PanelEdge* = enum
    peTop
    peBottom

  PanelConfig* = object
    edge*: PanelEdge
    output*: int32
    height*: int32
    margin*: int32
    namespace*: string

func defaultPanelConfig*(output = 0'i32): PanelConfig =
  PanelConfig(
    edge: peTop, output: output, height: 48, margin: 0, namespace: "toasty-panel"
  )

proc validate*(config: PanelConfig) =
  if config.output < 0:
    raise newException(ValueError, "panel output must be zero or greater")
  if config.height <= 0:
    raise newException(ValueError, "panel height must be greater than zero")
  if config.margin < 0:
    raise newException(ValueError, "panel margin cannot be negative")
  if config.namespace.len == 0:
    raise newException(ValueError, "panel namespace cannot be empty")
