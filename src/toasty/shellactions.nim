## Execution of desktop session actions with explicit confirmation handled by the UI.

import std/[options, os, osproc, strutils]

when defined(posix):
  import std/posix

import shellmodel

type SessionActionSpec* = object
  command*: string
  arguments*: seq[string]

proc configuredCommand(name: string): Option[SessionActionSpec] =
  let value = getEnv(name)
  if value.len == 0:
    return none(SessionActionSpec)
  let parts = parseCmdLine(value)
  if parts.len == 0:
    return none(SessionActionSpec)
  some(SessionActionSpec(command: parts[0], arguments: parts[1 .. ^1]))

proc sessionActionSpec*(action: SessionAction): Option[SessionActionSpec] =
  let environmentName =
    case action
    of saLock: "TOASTY_LOCK_COMMAND"
    of saLogout: "TOASTY_LOGOUT_COMMAND"
    of saRestart: "TOASTY_RESTART_COMMAND"
    of saSuspend: "TOASTY_SUSPEND_COMMAND"
    of saPoweroff: "TOASTY_POWEROFF_COMMAND"
  result = configuredCommand(environmentName)
  if result.isSome:
    return

  case action
  of saLock:
    for path in ["/usr/local/bin/waylock", "/usr/local/bin/swaylock"]:
      if fileExists(path):
        return some(SessionActionSpec(command: path))
  of saLogout:
    return none(SessionActionSpec)
  of saRestart:
    if fileExists("/sbin/shutdown"):
      return
        some(SessionActionSpec(command: "/sbin/shutdown", arguments: @["-r", "now"]))
  of saSuspend:
    if fileExists("/usr/sbin/zzz"):
      return some(SessionActionSpec(command: "/usr/sbin/zzz"))
  of saPoweroff:
    if fileExists("/sbin/shutdown"):
      return
        some(SessionActionSpec(command: "/sbin/shutdown", arguments: @["-p", "now"]))

proc sessionActionAvailable*(action: SessionAction): bool =
  if action == saLogout:
    return
      getEnv("TOASTY_SESSION_PID").len > 0 or
      configuredCommand("TOASTY_LOGOUT_COMMAND").isSome
  action.sessionActionSpec().isSome

proc startSessionCommand(spec: SessionActionSpec) =
  let process = startProcess(
    spec.command, args = spec.arguments, options = {poUsePath, poParentStreams}
  )
  process.close()

proc performSessionAction*(action: SessionAction): string =
  if action == saLogout and getEnv("TOASTY_LOGOUT_COMMAND").len == 0:
    let sessionPid = getEnv("TOASTY_SESSION_PID")
    if sessionPid.len == 0:
      return "The Toasty session supervisor PID is unavailable"
    try:
      when defined(posix):
        if posix.kill(sessionPid.parseInt().Pid, SIGTERM) != 0:
          return "Could not signal the Toasty session supervisor"
        return "Logging out"
      else:
        return "Logout requires a POSIX session"
    except ValueError:
      return "The Toasty session supervisor PID is invalid"

  let spec = action.sessionActionSpec()
  if spec.isNone:
    return action.sessionActionTitle() & " is not configured"
  try:
    spec.get().startSessionCommand()
    action.sessionActionTitle() & " requested"
  except CatchableError as error:
    action.sessionActionTitle() & " failed: " & error.msg
