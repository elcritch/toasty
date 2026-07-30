## Root module for toasty.

import toasty/[panelconfig, panelmodel, triad]

export panelconfig, panelmodel, triad

proc greet*(name: string): string =
  ## Returns a greeting for `name`.
  "hello, " & name
