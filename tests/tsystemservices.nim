import std/[options, unittest]

import toasty

suite "FreeBSD system service adapters":
  test "parses mixer volume and default network interface":
    let mixer =
      """
pcm4:mixer: <Audio> on hdaa1 (play/rec) (default)
    vol       = 0.75:0.75     pbk
"""
    let route =
      """
   route to: 0.0.0.0
  interface: wlan0
"""

    check mixer.parseVolume() == some(75)
    check route.parseDefaultInterface() == "wlan0"

  test "probes quick settings through an injected command runner":
    let runner: CommandRunner = proc(
        command: string, arguments: seq[string]
    ): CommandResult =
      discard arguments
      case command
      of "/usr/sbin/mixer":
        CommandResult(output: "vol = 0.42:0.42 pbk", exitCode: 0)
      of "/sbin/route":
        CommandResult(output: "interface: em0", exitCode: 0)
      of "/usr/bin/backlight":
        CommandResult(output: "63", exitCode: 0)
      else:
        CommandResult(exitCode: 1)

    let settings = probeQuickSettings(runner)
    check settings.audioAvailable
    check settings.volume == 42
    check settings.networkConnected
    check settings.networkInterface == "em0"
    check settings.brightness == some(63)
