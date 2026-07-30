import toasty/shellapp

when isMainModule:
  try:
    runToastyShell()
  except CatchableError as error:
    stderr.writeLine("toasty_panel: ", error.msg)
    quit(QuitFailure)
