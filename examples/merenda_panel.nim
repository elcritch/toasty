import std/[os, strutils]

import merenda/nimkit
import sigils/selectors

import toasty

proc environmentInt(name: string, fallback: int32): int32 =
  let value = getEnv(name)
  if value.len == 0:
    return fallback
  value.parseInt().int32

var panelConfig = defaultPanelConfig(output = environmentInt("TOASTY_PANEL_OUTPUT", 0))
panelConfig.height = environmentInt("TOASTY_PANEL_HEIGHT", panelConfig.height)
panelConfig.margin = environmentInt("TOASTY_PANEL_MARGIN", panelConfig.margin)
panelConfig.validate()

let
  layerConfig = LayerSurfaceConfig(
    layer: lslTop,
    anchors:
      if panelConfig.edge == peTop:
        {lsaTop, lsaLeft, lsaRight}
      else:
        {lsaBottom, lsaLeft, lsaRight},
    margins: LayerSurfaceMargins(
      top: panelConfig.margin,
      right: panelConfig.margin,
      bottom: panelConfig.margin,
      left: panelConfig.margin,
    ),
    exclusiveZone: panelConfig.height + panelConfig.margin,
    keyboardMode: lskNone,
    output: panelConfig.output,
    namespace: panelConfig.namespace,
  )
  app = sharedApplication()
  window = newLayerSurfaceWindow(
    "Toasty Panel",
    frame = rect(0, 0, 1280, panelConfig.height.float32),
    config = layerConfig,
  )
  root = newView()
  layout = newStackView(laHorizontal)
  title = newTitleLabel("Toasty")
  status = newStatusLabel("Merenda · River · GPU")
  inputButton = newButton("Panel input: ready")
  inputAction = actionSelector("recordPanelInput")

var clickCount = 0

proc recordPanelInput(sender: DynamicAgent) =
  if sender.isNil:
    return
  inc clickCount
  stderr.writeLine "panel-input: click_count=", clickCount

inputButton.target = newActionTarget(inputAction, recordPanelInput)
inputButton.action = inputAction

root.usesThemedRootBackground = false
root.background = color(0.055, 0.075, 0.12, 1.0)
layout.spacing = 14.0
layout.alignment = svaCenter
layout.distribution = svdNatural
layout.addArrangedSubview(title, status)
layout.addFlexibleSpacer()
layout.addArrangedSubview(inputButton)

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(insets(8.0, 12.0, 8.0, 12.0)),
  edges = {leLeft, leTop, leRight, leBottom},
)

app.runWindow(window, root)
