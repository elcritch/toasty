## Root module for toasty.

import toasty/panelconfig

export panelconfig

proc greet*(name: string): string =
  ## Returns a greeting for `name`.
  "hello, " & name
