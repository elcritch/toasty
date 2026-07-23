# Toasty

Toasty is a FreeBSD-first Wayland desktop built with
[Merenda](https://github.com/elcritch/merenda). River provides the compositor,
Triad manages windows, and Toasty provides the visible desktop shell.

The project is currently in its bootstrap stage. The first milestone is a
repeatable FreeBSD development session with these independent processes:

```text
river  <->  triad  <->  toasty
```

Keeping Triad external means the shell can be developed and restarted without
embedding the window manager or compositor.

## Set Up

Install Toasty's Nim dependencies with Atlas:

```sh
atlas install
```

Do not use Nimble for dependency resolution.

## Build Triad on FreeBSD

The `triad` task checks out Triad under `deps/triad`, replays Triad's committed
lockfile with Atlas, applies the temporary FreeBSD `fsnotify` compatibility
patch, and invokes the built-in `atlas-run build` command:

```sh
nim triad
```

For an optimized build:

```sh
nim triadRelease
```

The binaries are written to:

```text
deps/triad/triad
deps/triad/triad_niri
deps/triad/triad_mirror
```

The task intentionally uses `atlas rep nimble.lock`: Atlas can replay the
upstream lockfile directly, so the dependency revisions match Triad's known
build without invoking Nimble or Nix. Use the built-in `atlas-run build`
command rather than Triad task names such as `buildRelease`, because some
upstream task bodies currently invoke Nimble.

To update the Triad checkout:

```sh
git -C deps/triad pull --ff-only
nim triad
```

The task does not update it automatically, protecting any local Triad work.

## Test

Run the Toasty tests:

```sh
nim test
```

Run one test:

```sh
nim r tests/ttoasty.nim
```

## Project Layout

- `src/`: Toasty shell modules.
- `tests/`: deterministic unit tests.
- `config.nims`: Toasty tests and Atlas-only Triad build tasks.
- `patches/`: temporary upstream compatibility patches.
