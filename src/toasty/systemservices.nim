## FreeBSD desktop service probes and command construction.

import std/[options, os, osproc, strutils]

type
  CommandResult* = object
    output*: string
    exitCode*: int

  CommandRunner* =
    proc(command: string, arguments: seq[string]): CommandResult {.closure.}

  QuickSettingsState* = object
    volume*: int
    audioAvailable*: bool
    networkInterface*: string
    networkConnected*: bool
    brightness*: Option[int]

proc systemCommandRunner*(command: string, arguments: seq[string]): CommandResult =
  var parts = @[quoteShell(command)]
  for argument in arguments:
    parts.add(quoteShell(argument))
  let completed = execCmdEx(parts.join(" "))
  CommandResult(output: completed.output, exitCode: completed.exitCode)

proc parseVolume*(output: string): Option[int] =
  for line in output.splitLines():
    let marker = line.find("vol")
    let equals = line.find('=')
    if marker >= 0 and equals > marker:
      let channels = line[equals + 1 .. ^1].strip().splitWhitespace()[0].split(':')
      if channels.len > 0:
        try:
          return some(clamp((channels[0].parseFloat() * 100.0).int, 0, 100))
        except ValueError:
          discard
  none(int)

proc parseDefaultInterface*(output: string): string =
  for line in output.splitLines():
    let cleaned = line.strip()
    if cleaned.startsWith("interface:"):
      return cleaned["interface:".len .. ^1].strip()

proc parseBrightness*(output: string): Option[int] =
  for word in output.splitWhitespace():
    try:
      return some(clamp(word.parseInt(), 0, 100))
    except ValueError:
      discard
  none(int)

proc probeQuickSettings*(runner: CommandRunner): QuickSettingsState =
  let audio = runner("/usr/sbin/mixer", @[])
  if audio.exitCode == 0:
    let volume = audio.output.parseVolume()
    if volume.isSome:
      result.volume = volume.get()
      result.audioAvailable = true

  let network = runner("/sbin/route", @["-n", "get", "default"])
  if network.exitCode == 0:
    result.networkInterface = network.output.parseDefaultInterface()
    result.networkConnected = result.networkInterface.len > 0

  let brightness = runner("/usr/bin/backlight", @["-q"])
  if brightness.exitCode == 0:
    result.brightness = brightness.output.parseBrightness()

proc probeQuickSettings*(): QuickSettingsState =
  let runner: CommandRunner = systemCommandRunner
  runner.probeQuickSettings()

proc setVolume*(runner: CommandRunner, volume: int): CommandResult =
  let fraction = formatFloat(clamp(volume, 0, 100).float / 100.0, ffDecimal, 2)
  runner("/usr/sbin/mixer", @["vol=" & fraction])

proc setBrightness*(runner: CommandRunner, brightness: int): CommandResult =
  runner("/usr/bin/backlight", @[$clamp(brightness, 0, 100)])

proc commandExists*(path: string): bool =
  if path.contains(DirSep):
    fileExists(path)
  else:
    findExe(path).len > 0
