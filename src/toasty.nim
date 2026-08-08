## Root module for toasty.

import
  toasty/[
    desktopentries, notificationdaemon, notifications, panelconfig, panelmodel,
    shellmodel, systemservices, triad,
  ]

export
  desktopentries, notificationdaemon, notifications, panelconfig, panelmodel,
  shellmodel, systemservices, triad

proc greet*(name: string): string =
  ## Returns a greeting for `name`.
  "hello, " & name
