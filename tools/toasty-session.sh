#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
nim_bin=${TOASTY_NIM:-}
atlas_bin_dir=${TOASTY_ATLAS_BIN_DIR:-"$HOME/.nimble/bin"}

PATH="$atlas_bin_dir:/usr/local/nim/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
export PATH

if [ -z "$nim_bin" ]; then
  nim_bin=$(command -v nim 2>/dev/null || true)
fi
if [ -z "$nim_bin" ] && [ -x /usr/local/nim/bin/nim ]; then
  nim_bin=/usr/local/nim/bin/nim
fi
if [ -z "$nim_bin" ]; then
  printf '%s\n' 'toasty-session: Nim was not found' >&2
  exit 1
fi

cd "$project_dir"
exec "$nim_bin" sessionRelease
