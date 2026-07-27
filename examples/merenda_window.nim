import merenda/nimkit

let
  app = sharedApplication()
  window = newWindow("Toasty Merenda Smoke", frame = rect(80, 80, 480, 160))
  root = newView()
  layout = newStackView(laVertical)
  label = newTitleLabel("Toasty on FreeBSD")

layout.addArrangedSubview(label)
root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(insets(24.0, 24.0, 0.0, 24.0)),
  edges = {leLeft, leTop, leRight},
)

app.runWindow(window, root)
