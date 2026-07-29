import std/[json, os, strutils]

--mm:
  atomicArc
--threads:
  on

proc shellCommand(parts: openArray[string]): string =
  for part in parts:
    if result.len > 0:
      result.add(' ')
    result.add(quoteShell(part))

proc requiredTool(envName, fallback: string): string =
  let configured = getEnv(envName, fallback)
  result = findExe(configured)
  if result.len == 0 and fileExists(configured):
    result = configured
  if result.len == 0:
    raise newException(OSError, "missing command: " & configured)

proc commandSucceeds(parts: openArray[string]): bool =
  let (_, exitCode) = gorgeEx(shellCommand(parts))
  exitCode == 0

proc applyPatch(gitBin, checkoutDir, patchPath, description: string) =
  let
    applyArgs = @[gitBin, "-C", checkoutDir, "apply", patchPath]
    checkArgs = @[gitBin, "-C", checkoutDir, "apply", "--check", patchPath]
    reverseArgs =
      @[gitBin, "-C", checkoutDir, "apply", "--reverse", "--check", patchPath]

  if commandSucceeds(checkArgs):
    exec(shellCommand(applyArgs))
  elif not commandSucceeds(reverseArgs):
    raise newException(OSError, description & " patch no longer applies")

proc applyFreeBsdPatch(gitBin, triadDir, patchPath: string) =
  let fsnotifyDir = triadDir / "deps" / "fsnotify"
  applyPatch(gitBin, fsnotifyDir, patchPath, "the FreeBSD fsnotify")

proc applyLayerShellPatches(rootDir, gitBin: string) =
  for entry in [
    ("siwin", "siwin-layer-shell.patch"),
    ("figdraw", "figdraw-layer-shell.patch"),
    ("merenda", "merenda-layer-shell.patch"),
  ]:
    let
      dependency = entry[0]
      patchName = entry[1]
      dependencyDir = rootDir / "deps" / dependency
    if not dirExists(dependencyDir / ".git"):
      raise newException(
        OSError, dependency & " checkout is missing; run atlas install first"
      )
    applyPatch(
      gitBin,
      dependencyDir,
      rootDir / "patches" / patchName,
      "the " & dependency & " layer-shell",
    )

proc buildTriad(release: bool) =
  let
    rootDir = thisDir()
    triadDir = getEnv("TOASTY_TRIAD_DIR", rootDir / "deps" / "triad")
    patchPath = rootDir / "patches" / "fsnotify-freebsd.patch"
    atlasBin = requiredTool("TOASTY_ATLAS", "atlas")
    atlasRunBin = requiredTool("TOASTY_ATLAS_RUN", "atlas-run")
    gitBin = requiredTool("TOASTY_GIT", "git")
    nimBin = requiredTool("TOASTY_NIM", "nim")

  if not dirExists(triadDir):
    mkDir(parentDir(triadDir))
    exec(
      shellCommand(@[gitBin, "clone", "https://github.com/greenm01/triad", triadDir])
    )
  elif not dirExists(triadDir / ".git"):
    raise newException(OSError, triadDir & " exists but is not a Git checkout")

  if not fileExists(triadDir / "atlas.config") and
      not fileExists(triadDir / "deps" / "atlas.config"):
    withDir triadDir:
      exec(shellCommand(@[atlasBin, "init"]))

  withDir triadDir:
    exec(
      shellCommand(
        @[
          atlasBin,
          "--project=" & triadDir,
          "--noexec",
          "rep",
          triadDir / "nimble.lock",
        ]
      )
    )

  when defined(freebsd):
    applyFreeBsdPatch(gitBin, triadDir, patchPath)

  var buildArgs =
    @[
      atlasRunBin,
      "--project=" & triadDir,
      "--nim=" & nimBin,
      "build",
      "--",
      "--hints:off",
    ]
  let lock = parseJson(readFile(triadDir / "nimble.lock"))
  for dependency, _ in lock["packages"]:
    if dependency == "nim":
      continue
    let dependencyDir = triadDir / "deps" / dependency
    if dirExists(dependencyDir / "src"):
      buildArgs.add("--path:" & dependencyDir / "src")
    elif dirExists(dependencyDir):
      buildArgs.add("--path:" & dependencyDir)
  if release:
    buildArgs.add("-d:release")
    buildArgs.add("--opt:speed")
    buildArgs.add("--passL:-s")

  let hadDevMode = existsEnv("TRIAD_DEV_MODE")
  let previousDevMode = getEnv("TRIAD_DEV_MODE")
  putEnv("TRIAD_DEV_MODE", "0")
  try:
    exec(shellCommand(buildArgs))
    for binary in ["triad", "triad_niri", "triad_mirror"]:
      if not fileExists(triadDir / binary):
        raise newException(OSError, "Triad build did not produce " & binary)
  finally:
    if hadDevMode:
      putEnv("TRIAD_DEV_MODE", previousDevMode)
    else:
      delEnv("TRIAD_DEV_MODE")

proc buildMerendaWindow(run: bool) =
  let
    rootDir = thisDir()
    merendaDir = rootDir / "deps" / "merenda"
    examplePath = rootDir / "examples" / "merenda_window.nim"
    nimBin = requiredTool("TOASTY_NIM", "nim")

  if not dirExists(merendaDir / ".git"):
    raise newException(OSError, "Merenda checkout is missing; run atlas install first")

  var buildArgs = @[nimBin, "c", "--hints:off", "--path:" & rootDir / "src"]
  if run:
    buildArgs.add("-r")
  buildArgs.add(examplePath)

  withDir rootDir:
    exec(shellCommand(buildArgs))

proc buildMerendaPanel(run: bool) =
  let
    rootDir = thisDir()
    examplePath = rootDir / "examples" / "merenda_panel.nim"
    gitBin = requiredTool("TOASTY_GIT", "git")
    nimBin = requiredTool("TOASTY_NIM", "nim")

  applyLayerShellPatches(rootDir, gitBin)

  var buildArgs = @[nimBin, "c", "--hints:off", "--path:" & rootDir / "src"]
  if run:
    buildArgs.add("-r")
  buildArgs.add(examplePath)

  withDir rootDir:
    exec(shellCommand(buildArgs))

proc buildTriadProbe(run: bool) =
  let
    rootDir = thisDir()
    examplePath = rootDir / "examples" / "triad_probe.nim"
    nimBin = requiredTool("TOASTY_NIM", "nim")

  var buildArgs = @[nimBin, "c", "--hints:off", "--path:" & rootDir / "src"]
  if run:
    buildArgs.add("-r")
  buildArgs.add(examplePath)

  withDir rootDir:
    exec(shellCommand(buildArgs))

task test, "run unit tests":
  for testFile in listFiles("tests/"):
    if testFile.endsWith(".nim") and testFile.splitFile().name.startsWith("t"):
      exec("nim c -r " & quoteShell(testFile))

task triad, "build the external Triad manager with Atlas":
  buildTriad(release = false)

task triadRelease, "build an optimized external Triad manager with Atlas":
  buildTriad(release = true)

task merendaWindow, "build the minimal Merenda Wayland window":
  buildMerendaWindow(run = false)

task merendaWindowRun, "build and run the minimal Merenda Wayland window":
  buildMerendaWindow(run = true)

task merendaPanel, "build the Merenda Wayland layer-shell panel":
  buildMerendaPanel(run = false)

task merendaPanelRun, "build and run the Merenda Wayland layer-shell panel":
  buildMerendaPanel(run = true)

task triadProbe, "build the typed Triad IPC probe":
  buildTriadProbe(run = false)

task triadProbeRun, "build and run the typed Triad IPC probe":
  buildTriadProbe(run = true)

task sessionSmoke, "start the River, Triad, and WayVNC smoke session":
  let
    rootDir = thisDir()
    shellBin = requiredTool("TOASTY_SH", "sh")
    sessionScript = rootDir / "tools" / "session-smoke.sh"
  exec(shellCommand(@[shellBin, sessionScript]))

task panelSmoke, "start the Merenda panel in the GPU WayVNC smoke session":
  let
    rootDir = thisDir()
    shellBin = requiredTool("TOASTY_SH", "sh")
    sessionScript = rootDir / "tools" / "session-smoke.sh"
    panelBin = rootDir / "examples" / "merenda_panel"

  buildMerendaPanel(run = false)
  let
    hadPanelBin = existsEnv("TOASTY_SESSION_PANEL_BIN")
    previousPanelBin = getEnv("TOASTY_SESSION_PANEL_BIN")
  putEnv("TOASTY_SESSION_PANEL_BIN", panelBin)
  try:
    exec(shellCommand(@[shellBin, sessionScript]))
  finally:
    if hadPanelBin:
      putEnv("TOASTY_SESSION_PANEL_BIN", previousPanelBin)
    else:
      delEnv("TOASTY_SESSION_PANEL_BIN")
