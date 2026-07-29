## Root module for toasty.

import toasty/[panelconfig, triad]

export panelconfig, triad

proc greet*(name: string): string =
  ## Returns a greeting for `name`.
  "hello, " & name
