import std/[os, strutils]

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

proc applyFreeBsdPatch(gitBin, triadDir, patchPath: string) =
  let fsnotifyDir = triadDir / "deps" / "fsnotify"
  let applyArgs = @[gitBin, "-C", fsnotifyDir, "apply", patchPath]
  let checkArgs = @[gitBin, "-C", fsnotifyDir, "apply", "--check", patchPath]
  let reverseArgs =
    @[gitBin, "-C", fsnotifyDir, "apply", "--reverse", "--check", patchPath]

  if commandSucceeds(checkArgs):
    exec(shellCommand(applyArgs))
  elif not commandSucceeds(reverseArgs):
    raise newException(OSError, "the FreeBSD fsnotify patch no longer applies")

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
    exec(shellCommand(@[atlasBin, "--noexec", "rep", "nimble.lock"]))

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
  if release:
    buildArgs.add("-d:release")
    buildArgs.add("--opt:speed")
    buildArgs.add("--passL:-s")

  let hadDevMode = existsEnv("TRIAD_DEV_MODE")
  let previousDevMode = getEnv("TRIAD_DEV_MODE")
  putEnv("TRIAD_DEV_MODE", "0")
  try:
    exec(shellCommand(buildArgs))
  finally:
    if hadDevMode:
      putEnv("TRIAD_DEV_MODE", previousDevMode)
    else:
      delEnv("TRIAD_DEV_MODE")

task test, "run unit tests":
  for testFile in listFiles("tests/"):
    if testFile.endsWith(".nim") and testFile.splitFile().name.startsWith("t"):
      exec("nim c -r " & quoteShell(testFile))

task triad, "build the external Triad manager with Atlas":
  buildTriad(release = false)

task triadRelease, "build an optimized external Triad manager with Atlas":
  buildTriad(release = true)

task sessionSmoke, "start the River, Triad, and WayVNC smoke session":
  let
    rootDir = thisDir()
    shellBin = requiredTool("TOASTY_SH", "sh")
    sessionScript = rootDir / "tools" / "session-smoke.sh"
  exec(shellCommand(@[shellBin, sessionScript]))
