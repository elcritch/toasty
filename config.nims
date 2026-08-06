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

proc buildTriad(release: bool) =
  let
    rootDir = thisDir()
    existingTriadDir = rootDir / "deps" / "triad"
    defaultTriadDir =
      if dirExists(existingTriadDir): existingTriadDir
      else: rootDir / "external" / "triad"
    triadDir = getEnv("TOASTY_TRIAD_DIR", defaultTriadDir)
    patchPath = rootDir / "patches" / "fsnotify-freebsd.patch"
    atlasBin = requiredTool("TOASTY_ATLAS", "atlas")
    atlasRunBin = requiredTool("TOASTY_ATLAS_RUN", "atlas-run")
    gitBin = requiredTool("TOASTY_GIT", "git")
    nimBin = requiredTool("TOASTY_NIM", "nim")
    lockPath = triadDir / "nimble.lock"

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

  let lock = parseJson(readFile(lockPath))
  var missingDependency = false
  for dependency, _ in lock["packages"]:
    if dependency != "nim" and not dirExists(triadDir / "deps" / dependency):
      missingDependency = true

  if missingDependency:
    withDir triadDir:
      exec(
        shellCommand(
          @[
            atlasBin,
            "--packagesRepo",
            "--noexec",
            "rep",
            lockPath.extractFilename,
          ]
        )
      )
  else:
    withDir triadDir:
      exec(
        shellCommand(
          @[atlasBin, "--project=" & triadDir, "--noexec", "rep", lockPath]
        )
      )

  for dependency, _ in lock["packages"]:
    if dependency != "nim" and not dirExists(triadDir / "deps" / dependency):
      raise newException(
        OSError, "Atlas did not materialize Triad dependency: " & dependency
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
    nimBin = requiredTool("TOASTY_NIM", "nim")

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

proc buildToastyPanel(run: bool, release = false) =
  let
    rootDir = thisDir()
    examplePath = rootDir / "examples" / "toasty_panel.nim"
    nimBin = requiredTool("TOASTY_NIM", "nim")

  var buildArgs = @[nimBin, "c", "--hints:off", "--path:" & rootDir / "src"]
  if release:
    buildArgs.add("-d:release")
    buildArgs.add("--opt:speed")
  if run:
    buildArgs.add("-r")
  buildArgs.add(examplePath)

  withDir rootDir:
    exec(shellCommand(buildArgs))

proc runToastySession(release, check: bool) =
  let
    rootDir = thisDir()
    shellBin = requiredTool("TOASTY_SH", "sh")
    scriptName =
      if check: "session-check.sh"
      else: "session.sh"
    sessionScript = rootDir / "tools" / scriptName

  buildTriad(release)
  buildToastyPanel(run = false, release = release)
  exec(shellCommand(@[shellBin, sessionScript]))

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

task toastyPanel, "build the subscription-driven Toasty panel":
  buildToastyPanel(run = false)

task toastyPanelRun, "build and run the subscription-driven Toasty panel":
  buildToastyPanel(run = true)

task sessionDev, "build and run the supervised development session":
  runToastySession(release = false, check = false)

task sessionRelease, "build and run the supervised release session":
  runToastySession(release = true, check = false)

task sessionCheck, "verify supervised component restarts and clean shutdown":
  runToastySession(release = false, check = true)

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

task sliceSmoke, "start the subscription-driven panel in the GPU WayVNC session":
  let
    rootDir = thisDir()
    shellBin = requiredTool("TOASTY_SH", "sh")
    sessionScript = rootDir / "tools" / "session-smoke.sh"
    panelBin = rootDir / "examples" / "toasty_panel"

  buildToastyPanel(run = false)
  let
    hadPanelBin = existsEnv("TOASTY_SESSION_PANEL_BIN")
    previousPanelBin = getEnv("TOASTY_SESSION_PANEL_BIN")
    hadPanelKind = existsEnv("TOASTY_SESSION_PANEL_KIND")
    previousPanelKind = getEnv("TOASTY_SESSION_PANEL_KIND")
  putEnv("TOASTY_SESSION_PANEL_BIN", panelBin)
  putEnv("TOASTY_SESSION_PANEL_KIND", "toasty")
  try:
    exec(shellCommand(@[shellBin, sessionScript]))
  finally:
    if hadPanelBin:
      putEnv("TOASTY_SESSION_PANEL_BIN", previousPanelBin)
    else:
      delEnv("TOASTY_SESSION_PANEL_BIN")
    if hadPanelKind:
      putEnv("TOASTY_SESSION_PANEL_KIND", previousPanelKind)
    else:
      delEnv("TOASTY_SESSION_PANEL_KIND")
