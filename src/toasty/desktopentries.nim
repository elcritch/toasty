## Discovery and launch preparation for XDG desktop application entries.

import std/[algorithm, options, os, osproc, strutils]

type
  DesktopApplication* = object
    id*: string
    name*: string
    comment*: string
    keywords*: seq[string]
    executable*: string
    icon*: string
    workingDirectory*: string
    terminal*: bool
    sourcePath*: string

  LaunchSpec* = object
    command*: string
    arguments*: seq[string]
    workingDirectory*: string

proc splitList(value: string): seq[string] =
  for item in value.split(';'):
    let cleaned = item.strip()
    if cleaned.len > 0:
      result.add(cleaned)

func parseDesktopBool(value: string): bool =
  value.strip().toLowerAscii() == "true"

proc parseDesktopEntry*(contents, sourcePath: string): Option[DesktopApplication] =
  var
    inDesktopEntry = false
    entryType = ""
    hidden = false
    noDisplay = false
    application = DesktopApplication(sourcePath: sourcePath)

  for rawLine in contents.splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith('#'):
      continue
    if line.startsWith('[') and line.endsWith(']'):
      inDesktopEntry = line == "[Desktop Entry]"
    elif inDesktopEntry:
      let separator = line.find('=')
      if separator > 0:
        let
          key = line[0 ..< separator]
          value = line[separator + 1 .. ^1]
        case key
        of "Type":
          entryType = value
        of "Name":
          application.name = value
        of "Comment":
          application.comment = value
        of "Keywords":
          application.keywords = value.splitList()
        of "Exec":
          application.executable = value
        of "Icon":
          application.icon = value
        of "Path":
          application.workingDirectory = value
        of "Terminal":
          application.terminal = value.parseDesktopBool()
        of "Hidden":
          hidden = value.parseDesktopBool()
        of "NoDisplay":
          noDisplay = value.parseDesktopBool()
        else:
          discard

  if entryType != "Application" or hidden or noDisplay or application.name.len == 0 or
      application.executable.len == 0:
    return none(DesktopApplication)

  application.id = sourcePath.splitFile().name
  some(application)

proc xdgApplicationDirs*(): seq[string] =
  let dataHome = getEnv("XDG_DATA_HOME", getHomeDir() / ".local" / "share")
  result.add(dataHome / "applications")
  let dataDirs = getEnv("XDG_DATA_DIRS", "/usr/local/share:/usr/share")
  for directory in dataDirs.split(PathSep):
    let cleaned = directory.strip()
    if cleaned.len > 0:
      result.add(cleaned / "applications")

proc discoverApplications*(
    directories = xdgApplicationDirs()
): seq[DesktopApplication] =
  var seen: seq[string]
  for directory in directories:
    if not dirExists(directory):
      continue
    for path in walkFiles(directory / "*.desktop"):
      try:
        let parsed = parseDesktopEntry(readFile(path), path)
        if parsed.isSome and parsed.get().id notin seen:
          seen.add(parsed.get().id)
          result.add(parsed.get())
      except CatchableError:
        discard
  result.sort(
    proc(left, right: DesktopApplication): int =
      cmp(left.name.toLowerAscii(), right.name.toLowerAscii())
  )

proc expandDesktopToken(
    token: string, application: DesktopApplication
): Option[string] =
  if token in ["%f", "%F", "%u", "%U", "%i"]:
    return none(string)

  var expanded = ""
  var index = 0
  while index < token.len:
    if token[index] == '%' and index + 1 < token.len:
      case token[index + 1]
      of '%':
        expanded.add('%')
      of 'c':
        expanded.add(application.name)
      of 'k':
        expanded.add(application.sourcePath)
      of 'f', 'F', 'u', 'U', 'i':
        discard
      else:
        expanded.add(token[index])
        expanded.add(token[index + 1])
      index += 2
    else:
      expanded.add(token[index])
      inc index
  if expanded.len > 0:
    some(expanded)
  else:
    none(string)

proc launchSpec*(application: DesktopApplication, terminal = ""): LaunchSpec =
  let fields = parseCmdLine(application.executable)
  if fields.len == 0:
    raise newException(ValueError, "desktop entry has an empty Exec command")

  var expanded: seq[string]
  for field in fields:
    let value = field.expandDesktopToken(application)
    if value.isSome:
      expanded.add(value.get())
  if expanded.len == 0:
    raise newException(ValueError, "desktop entry Exec command has no executable")

  result = LaunchSpec(
    command: expanded[0],
    arguments: expanded[1 .. ^1],
    workingDirectory: application.workingDirectory,
  )
  if application.terminal:
    let terminalCommand =
      if terminal.len > 0:
        terminal
      else:
        getEnv("TOASTY_TERMINAL", "foot")
    result.arguments = @["-e", result.command] & result.arguments
    result.command = terminalCommand

proc launch*(application: DesktopApplication) =
  let spec = application.launchSpec()
  let process = startProcess(
    spec.command,
    workingDir = spec.workingDirectory,
    args = spec.arguments,
    options = {poUsePath, poParentStreams},
  )
  process.close()
