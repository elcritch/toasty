#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
triad_bin=${TOASTY_TRIAD_BIN:-"$project_dir/deps/triad/triad"}
triad_config=${TOASTY_TRIAD_CONFIG:-"$project_dir/deps/triad/config.default.kdl"}
river_bin=${TOASTY_RIVER_BIN:-river}
wayvnc_bin=${TOASTY_WAYVNC_BIN:-wayvnc}
wayland_info_bin=${TOASTY_WAYLAND_INFO_BIN:-wayland-info}
client_bin=${TOASTY_SESSION_CLIENT:-foot}
vnc_address=${TOASTY_VNC_ADDRESS:-127.0.0.1}
vnc_port=${TOASTY_VNC_PORT:-5905}
replace_session=${TOASTY_SESSION_REPLACE:-0}
run_once=${TOASTY_SESSION_ONCE:-0}

state_home=${XDG_STATE_HOME:-"$HOME/.local/state"}
log_root=${TOASTY_SESSION_LOG_DIR:-"$state_home/toasty/session-smoke"}
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
log_dir="$log_root/$timestamp"
runtime_dir=
river_pid=
wayvnc_pid=
cleaned=0

fail() {
  printf 'session-smoke: %s\n' "$*" >&2
  exit 1
}

find_command() {
  command -v "$1" 2>/dev/null || fail "missing command: $1"
}

process_ids() {
  process_name=$1
  pgrep -x "$process_name" 2>/dev/null || true
}

wait_for_exit() {
  process_name=$1
  attempts=0
  while [ "$attempts" -lt 50 ]; do
    [ -z "$(process_ids "$process_name")" ] && return 0
    attempts=$((attempts + 1))
    sleep 0.1
  done
  return 1
}

stop_existing_session() {
  existing=
  for process_name in wayvnc river sway; do
    ids=$(process_ids "$process_name")
    if [ -n "$ids" ]; then
      existing="${existing}${process_name}: ${ids}
"
    fi
  done

  [ -z "$existing" ] && return 0
  if [ "$replace_session" != 1 ]; then
    printf '%s' "$existing" >&2
    fail "an existing graphical session is running; set TOASTY_SESSION_REPLACE=1 to replace it"
  fi

  printf 'session-smoke: replacing existing session:\n%s' "$existing"
  for process_name in wayvnc river sway; do
    ids=$(process_ids "$process_name")
    [ -z "$ids" ] || kill $ids
  done
  for process_name in wayvnc river sway; do
    wait_for_exit "$process_name" ||
      fail "$process_name did not stop; refusing to force-kill it"
  done
}

cleanup() {
  [ "$cleaned" -eq 0 ] || return
  cleaned=1
  trap - EXIT INT TERM HUP
  if [ -n "$wayvnc_pid" ] && kill -0 "$wayvnc_pid" 2>/dev/null; then
    kill "$wayvnc_pid" 2>/dev/null || true
    wait "$wayvnc_pid" 2>/dev/null || true
  fi
  if [ -n "$river_pid" ] && kill -0 "$river_pid" 2>/dev/null; then
    kill "$river_pid" 2>/dev/null || true
    wait "$river_pid" 2>/dev/null || true
  fi
  if [ -n "$runtime_dir" ] && [ -d "$runtime_dir" ]; then
    rm -r -- "$runtime_dir"
  fi
}

wait_for_file() {
  path=$1
  owner_pid=$2
  label=$3
  attempts=0
  while [ "$attempts" -lt 100 ]; do
    [ -S "$path" ] && return 0
    kill -0 "$owner_pid" 2>/dev/null ||
      fail "$label exited before creating $path"
    attempts=$((attempts + 1))
    sleep 0.1
  done
  fail "timed out waiting for $path"
}

wait_for_window() {
  app_id=$1
  attempts=0
  while [ "$attempts" -lt 100 ]; do
    if run_triad_msg windows 2>/dev/null | grep -q "\"app_id\":\"$app_id\""; then
      return 0
    fi
    kill -0 "$river_pid" 2>/dev/null ||
      fail "River exited while waiting for app ID $app_id"
    attempts=$((attempts + 1))
    sleep 0.1
  done
  fail "Triad did not report the test window app ID: $app_id"
}

protocol_version() {
  interface_name=$1
  sed -n \
    "s/^interface: '$interface_name',[[:space:]]*version:[[:space:]]*\\([0-9][0-9]*\\).*/\\1/p" \
    "$log_dir/wayland-info.log" | head -n 1
}

require_protocol() {
  interface_name=$1
  minimum=$2
  version=$(protocol_version "$interface_name")
  [ -n "$version" ] ||
    fail "River did not advertise required protocol $interface_name"
  [ "$version" -ge "$minimum" ] ||
    fail "River advertised $interface_name v$version; Triad requires v$minimum"
  printf '%s v%s (requires v%s)\n' "$interface_name" "$version" "$minimum" \
    >>"$log_dir/protocol-check.log"
}

run_triad_msg() {
  env XDG_RUNTIME_DIR="$runtime_dir" "$triad_bin" msg "$@"
}

record_command() {
  printf '\n$ triad msg' >>"$log_dir/commands.log"
  for argument in "$@"; do
    printf ' %s' "$argument" >>"$log_dir/commands.log"
  done
  printf '\n' >>"$log_dir/commands.log"
  run_triad_msg "$@" >>"$log_dir/commands.log" 2>&1
}

[ "$(uname -s)" = FreeBSD ] ||
  fail "milestone 1 targets FreeBSD; found $(uname -s)"
[ -x "$triad_bin" ] || fail "Triad binary is not executable: $triad_bin"
[ -f "$triad_config" ] || fail "Triad config is missing: $triad_config"

river_bin=$(find_command "$river_bin")
wayvnc_bin=$(find_command "$wayvnc_bin")
wayland_info_bin=$(find_command "$wayland_info_bin")
client_bin=$(find_command "$client_bin")

mkdir -p -- "$log_dir"
ln -sfn -- "$log_dir" "$log_root/latest"
runtime_dir=$(mktemp -d "${TMPDIR:-/tmp}/toasty-session.XXXXXX")
chmod 700 "$runtime_dir"
trap cleanup EXIT INT TERM HUP

"$triad_bin" validate-config --config "$triad_config" \
  >"$log_dir/config-validation.log" 2>&1

stop_existing_session

export XDG_RUNTIME_DIR="$runtime_dir"
export WLR_BACKENDS=headless
export WLR_RENDERER=pixman
export WLR_HEADLESS_OUTPUTS=1
export TRIAD_BIN="$triad_bin"
export TRIAD_CONFIG="$triad_config"
export TRIAD_LOG_PATH="$log_dir/triad.log"
export XDG_CURRENT_DESKTOP=river
export XDG_SESSION_DESKTOP=river-triad
export XDG_SESSION_TYPE=wayland
unset WAYLAND_DISPLAY

"$river_bin" -log-level debug \
  -c 'exec "$TRIAD_BIN" --config "$TRIAD_CONFIG" >"$TRIAD_LOG_PATH" 2>&1' \
  >"$log_dir/river-triad.log" 2>&1 &
river_pid=$!

wait_for_file "$runtime_dir/triad.sock" "$river_pid" Triad

wayland_display=
attempts=0
while [ "$attempts" -lt 100 ]; do
  for socket_path in "$runtime_dir"/wayland-*; do
    if [ -S "$socket_path" ]; then
      wayland_display=${socket_path##*/}
      break
    fi
  done
  [ -n "$wayland_display" ] && break
  kill -0 "$river_pid" 2>/dev/null ||
    fail "River exited before creating a Wayland socket"
  attempts=$((attempts + 1))
  sleep 0.1
done
[ -n "$wayland_display" ] || fail "timed out waiting for River's Wayland socket"
export WAYLAND_DISPLAY="$wayland_display"

"$wayland_info_bin" >"$log_dir/wayland-info.log" 2>&1
require_protocol river_window_manager_v1 4
require_protocol river_xkb_bindings_v1 2
require_protocol wl_compositor 1
require_protocol wl_shm 1

{
  printf 'date_utc=%s\n' "$timestamp"
  printf 'host=%s\n' "$(hostname)"
  printf 'os=%s\n' "$(uname -K)"
  printf 'river=%s\n' "$("$river_bin" -version 2>&1)"
  printf 'wayvnc=%s\n' "$("$wayvnc_bin" --version 2>&1 | head -n 1)"
  printf 'triad_commit=%s\n' "$(git -C "$project_dir/deps/triad" rev-parse HEAD)"
  printf 'WAYLAND_DISPLAY=%s\n' "$WAYLAND_DISPLAY"
  printf 'XDG_RUNTIME_DIR=%s\n' "$XDG_RUNTIME_DIR"
  printf 'backend=%s\n' "$WLR_BACKENDS"
  printf 'renderer=%s\n' "$WLR_RENDERER"
  printf 'seat=wl_seat v%s (headless virtual input)\n' "$(protocol_version wl_seat)"
  printf 'vnc_address=%s\n' "$vnc_address"
  printf 'vnc_port=%s\n' "$vnc_port"
} >"$log_dir/environment.log"

record_command capabilities
record_command outputs
record_command spawn "$client_bin" -T Toasty-smoke-one -a toasty-smoke
wait_for_window toasty-smoke
record_command spawn "$client_bin" -T Toasty-smoke-two -a toasty-smoke
attempts=0
while [ "$attempts" -lt 100 ]; do
  window_count=$(run_triad_msg windows 2>/dev/null |
    grep -o '"app_id":"toasty-smoke"' | wc -l | tr -d ' ')
  [ "$window_count" -ge 2 ] && break
  kill -0 "$river_pid" 2>/dev/null ||
    fail "River exited while waiting for the second test window"
  attempts=$((attempts + 1))
  sleep 0.1
done
[ "$attempts" -lt 100 ] ||
  fail "Triad did not report both test windows"
record_command windows

focused_before=$(run_triad_msg focused-window |
  sed -n 's/.*"window":{"id":\([0-9][0-9]*\).*/\1/p')
[ -n "$focused_before" ] || fail "Triad did not report a focused test window"
record_command focus-prev
record_command focused-window
focused_previous=$(run_triad_msg focused-window |
  sed -n 's/.*"window":{"id":\([0-9][0-9]*\).*/\1/p')
[ -n "$focused_previous" ] ||
  fail "Triad did not report a focused window after focus-prev"
[ "$focused_previous" != "$focused_before" ] ||
  fail "focus-prev did not change the focused window"
record_command focus-next
record_command focused-window
focused_after=$(run_triad_msg focused-window |
  sed -n 's/.*"window":{"id":\([0-9][0-9]*\).*/\1/p')
[ "$focused_after" = "$focused_before" ] ||
  fail "focus-next did not restore the original focused window"
record_command focus-workspace 2
record_command workspaces
grep -q '"workspace_idx":2[^}]*"is_active":true' "$log_dir/commands.log" ||
  fail "focus-workspace 2 did not activate workspace 2"
record_command focus-workspace 1
record_command layout-grid
record_command layout-state
grep -q '"layout":"grid"' "$log_dir/commands.log" ||
  fail "layout-grid did not select the grid layout"
record_command layout-tile
record_command layout-state
grep -q '"layout":"tile"' "$log_dir/commands.log" ||
  fail "layout-tile did not select the tile layout"

"$wayvnc_bin" "$vnc_address" "$vnc_port" \
  >"$log_dir/wayvnc.log" 2>&1 &
wayvnc_pid=$!
attempts=0
while [ "$attempts" -lt 50 ]; do
  kill -0 "$wayvnc_pid" 2>/dev/null ||
    fail "WayVNC exited during startup"
  if nc -z "$vnc_address" "$vnc_port" 2>/dev/null; then
    break
  fi
  attempts=$((attempts + 1))
  sleep 0.1
done
[ "$attempts" -lt 50 ] ||
  fail "WayVNC did not listen on $vnc_address:$vnc_port"

printf '%s\n' \
  "session-smoke: River, Triad, clients, and WayVNC are running." \
  "session-smoke: connect to $vnc_address:$vnc_port (usually through an SSH tunnel)." \
  "session-smoke: logs: $log_dir"

if [ "$run_once" = 1 ]; then
  printf '%s\n' "session-smoke: automated smoke checks passed."
  exit 0
fi

printf '%s\n' "session-smoke: press Ctrl-C to stop the session."
while kill -0 "$river_pid" 2>/dev/null && kill -0 "$wayvnc_pid" 2>/dev/null; do
  wait "$river_pid" || break
done
fail "River or WayVNC exited; inspect $log_dir"
