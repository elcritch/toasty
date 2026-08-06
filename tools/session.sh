#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
session_script="$project_dir/tools/session.sh"
mode=${1:-run}

default_triad_dir="$project_dir/deps/triad"
if [ ! -d "$default_triad_dir" ] && [ -d "$project_dir/external/triad" ]; then
  default_triad_dir="$project_dir/external/triad"
fi
triad_bin=${TOASTY_TRIAD_BIN:-"$default_triad_dir/triad"}
triad_config=${TOASTY_TRIAD_CONFIG:-"$default_triad_dir/config.default.kdl"}
toasty_bin=${TOASTY_TOASTY_BIN:-"$project_dir/examples/toasty_panel"}
river_bin=${TOASTY_RIVER_BIN:-river}
wayvnc_bin=${TOASTY_WAYVNC_BIN:-wayvnc}
wayland_info_bin=${TOASTY_WAYLAND_INFO_BIN:-wayland-info}
vnc_address=${TOASTY_VNC_ADDRESS:-127.0.0.1}
vnc_port=${TOASTY_VNC_PORT:-5905}
replace_session=${TOASTY_SESSION_REPLACE:-0}
run_once=${TOASTY_SESSION_ONCE:-0}
restart_limit=${TOASTY_SESSION_RESTART_LIMIT:-5}
restart_delay=${TOASTY_SESSION_RESTART_DELAY:-1}
restart_reset=${TOASTY_SESSION_RESTART_RESET:-30}
startup_attempts=${TOASTY_SESSION_STARTUP_ATTEMPTS:-200}
headless_outputs=${TOASTY_SESSION_OUTPUTS:-1}
river_backends=${TOASTY_RIVER_BACKENDS:-headless}
river_renderer=${TOASTY_RIVER_RENDERER:-gles2}

state_home=${XDG_STATE_HOME:-"$HOME/.local/state"}
log_root=${TOASTY_SESSION_LOG_DIR:-"$state_home/toasty/session"}
runtime_base=${TMPDIR:-/tmp}

river_pid=
wayvnc_pid=
toasty_pid=
toasty_started_at=0
toasty_failures=0
runtime_dir=
log_dir=${TOASTY_SESSION_ACTIVE_LOG_DIR:-}
cleaned=0

fail() {
  printf 'toasty-session: %s\n' "$*" >&2
  exit 1
}

log_event() {
  event_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '%s %s\n' "$event_time" "$*" >>"$log_dir/session.log"
  printf 'toasty-session: %s\n' "$*"
}

find_command() {
  command -v "$1" 2>/dev/null || fail "missing command: $1"
}

is_unsigned_integer() {
  case "$1" in
    '' | *[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

process_is_running() {
  checked_pid=$1
  kill -0 "$checked_pid" 2>/dev/null || return 1
  process_state=$(ps -o state= -p "$checked_pid" 2>/dev/null |
    tr -d '[:space:]')
  case "$process_state" in
    '' | Z*) return 1 ;;
    *) return 0 ;;
  esac
}

wait_for_process_exit() {
  waited_pid=$1
  attempts=0
  while [ "$attempts" -lt 50 ]; do
    process_is_running "$waited_pid" || return 0
    attempts=$((attempts + 1))
    sleep 0.1
  done
  return 1
}

terminate_process() {
  label=$1
  terminated_pid=$2
  [ -n "$terminated_pid" ] || return 0
  process_is_running "$terminated_pid" || {
    wait "$terminated_pid" 2>/dev/null || true
    return 0
  }
  kill "$terminated_pid" 2>/dev/null || true
  if wait_for_process_exit "$terminated_pid"; then
    wait "$terminated_pid" 2>/dev/null || true
    log_event "$label stopped (pid $terminated_pid)"
  else
    log_event "$label did not stop within 5 seconds (pid $terminated_pid)"
  fi
}

triad_stopping=0
triad_pid=

stop_triad_supervisor() {
  triad_stopping=1
  if [ -n "$triad_pid" ] && process_is_running "$triad_pid"; then
    kill "$triad_pid" 2>/dev/null || true
  fi
}

clean_triad_supervisor() {
  trap - EXIT INT TERM HUP
  stop_triad_supervisor
  if [ -n "$triad_pid" ]; then
    wait "$triad_pid" 2>/dev/null || true
  fi
  rm -f -- "$log_dir/triad.pid" "$log_dir/triad-supervisor.pid"
}

run_triad_supervisor() {
  [ -n "$log_dir" ] ||
    fail "TOASTY_SESSION_ACTIVE_LOG_DIR is required by the Triad supervisor"
  mkdir -p -- "$log_dir"
  printf '%s\n' "$$" >"$log_dir/triad-supervisor.pid"
  trap clean_triad_supervisor EXIT
  trap stop_triad_supervisor INT TERM HUP

  failures=0
  while [ "$triad_stopping" -eq 0 ]; do
    started_at=$(date +%s)
    log_event "starting Triad (restart failures $failures/$restart_limit)"
    "$triad_bin" --config "$triad_config" >>"$log_dir/triad.log" 2>&1 &
    triad_pid=$!
    printf '%s\n' "$triad_pid" >"$log_dir/triad.pid"

    triad_status=0
    wait "$triad_pid" || triad_status=$?
    rm -f -- "$log_dir/triad.pid"
    [ "$triad_stopping" -eq 0 ] || return 0

    stopped_at=$(date +%s)
    lifetime=$((stopped_at - started_at))
    if [ "$lifetime" -ge "$restart_reset" ]; then
      failures=0
    fi
    failures=$((failures + 1))
    log_event "Triad exited with status $triad_status after ${lifetime}s"
    if [ "$failures" -gt "$restart_limit" ]; then
      log_event "Triad exceeded the restart limit"
      return 1
    fi
    sleep "$restart_delay"
  done
}

if [ "$mode" = triad-supervisor ]; then
  run_triad_supervisor
  exit 0
elif [ "$mode" != run ]; then
  fail "unknown mode: $mode"
fi

cleanup() {
  [ "$cleaned" -eq 0 ] || return
  cleaned=1
  trap - EXIT INT TERM HUP
  rm -f -- "$log_dir/ready" "$log_dir/toasty.ready"

  terminate_process Toasty "$toasty_pid"
  terminate_process WayVNC "$wayvnc_pid"

  triad_supervisor_pid=
  if [ -f "$log_dir/triad-supervisor.pid" ]; then
    triad_supervisor_pid=$(sed -n '1p' "$log_dir/triad-supervisor.pid")
  fi
  terminate_process "Triad supervisor" "$triad_supervisor_pid"
  terminate_process River "$river_pid"

  rm -f -- \
    "$log_dir/session.pid" \
    "$log_dir/river.pid" \
    "$log_dir/wayvnc.pid" \
    "$log_dir/toasty.pid" \
    "$log_dir/triad.pid" \
    "$log_dir/triad-supervisor.pid"

  if [ -n "$runtime_dir" ] && [ -d "$runtime_dir" ]; then
    case "$runtime_dir" in
      "$runtime_base"/toasty-session.*) rm -r -- "$runtime_dir" ;;
      *) log_event "refusing to remove unexpected runtime path: $runtime_dir" ;;
    esac
  fi
  log_event "session stopped"
}

stop_session() {
  cleanup
  exit 0
}

user_process_ids() {
  process_name=$1
  pgrep -U "$(id -u)" -x "$process_name" 2>/dev/null || true
}

stop_existing_session() {
  existing=
  existing_session_pid=
  latest_dir="$log_root/latest"
  if [ -f "$latest_dir/session.pid" ]; then
    candidate_pid=$(sed -n '1p' "$latest_dir/session.pid")
    if [ "$candidate_pid" != "$$" ] &&
        is_unsigned_integer "$candidate_pid" &&
        process_is_running "$candidate_pid"; then
      existing_session_pid=$candidate_pid
      existing="toasty-session: $candidate_pid
"
    fi
  fi

  for process_name in wayvnc river sway; do
    ids=$(user_process_ids "$process_name")
    if [ -n "$ids" ]; then
      existing="${existing}${process_name}: ${ids}
"
    fi
  done

  [ -z "$existing" ] && return 0
  if [ "$replace_session" != 1 ]; then
    printf '%s' "$existing" >&2
    fail "a graphical session is running; set TOASTY_SESSION_REPLACE=1 to replace it"
  fi

  printf 'toasty-session: replacing existing session:\n%s' "$existing"
  if [ -n "$existing_session_pid" ]; then
    kill "$existing_session_pid" 2>/dev/null || true
    wait_for_process_exit "$existing_session_pid" ||
      fail "the existing Toasty session did not stop"
  fi

  for process_name in wayvnc river sway; do
    ids=$(user_process_ids "$process_name")
    for existing_pid in $ids; do
      kill "$existing_pid" 2>/dev/null || true
    done
  done
  for process_name in wayvnc river sway; do
    ids=$(user_process_ids "$process_name")
    for existing_pid in $ids; do
      wait_for_process_exit "$existing_pid" ||
        fail "$process_name did not stop; refusing to force-kill it"
    done
  done
}

wait_for_file() {
  path=$1
  owner_pid=$2
  label=$3
  attempts=0
  while [ "$attempts" -lt "$startup_attempts" ]; do
    [ -f "$path" ] && return 0
    process_is_running "$owner_pid" ||
      fail "$label exited before creating $path"
    attempts=$((attempts + 1))
    sleep 0.1
  done
  fail "timed out waiting for $path"
}

wait_for_wayland_display() {
  attempts=0
  while [ "$attempts" -lt "$startup_attempts" ]; do
    for socket_path in "$runtime_dir"/wayland-*; do
      if [ -S "$socket_path" ]; then
        WAYLAND_DISPLAY=${socket_path##*/}
        export WAYLAND_DISPLAY
        return 0
      fi
    done
    process_is_running "$river_pid" ||
      fail "River exited before creating a Wayland socket"
    attempts=$((attempts + 1))
    sleep 0.1
  done
  fail "timed out waiting for River's Wayland socket"
}

run_triad_msg() {
  env XDG_RUNTIME_DIR="$runtime_dir" "$triad_bin" msg "$@"
}

wait_for_triad() {
  attempts=0
  while [ "$attempts" -lt "$startup_attempts" ]; do
    if run_triad_msg capabilities >/dev/null 2>&1; then
      return 0
    fi
    process_is_running "$river_pid" ||
      fail "River exited while waiting for Triad"
    if [ -f "$log_dir/triad-supervisor.pid" ]; then
      supervisor_pid=$(sed -n '1p' "$log_dir/triad-supervisor.pid")
      process_is_running "$supervisor_pid" ||
        fail "the Triad supervisor exited during startup"
    fi
    attempts=$((attempts + 1))
    sleep 0.1
  done
  fail "timed out waiting for Triad IPC readiness"
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
    fail "River advertised $interface_name v$version; requires v$minimum"
  printf '%s v%s (requires v%s)\n' "$interface_name" "$version" "$minimum" \
    >>"$log_dir/protocol-check.log"
}

log_contains_since() {
  pattern=$1
  first_line=$2
  tail -n "+$first_line" "$log_dir/toasty.log" 2>/dev/null |
    grep -q "$pattern"
}

wait_for_toasty() {
  first_line=$1
  attempts=0
  while [ "$attempts" -lt "$startup_attempts" ]; do
    renderer_ready=0
    if log_contains_since 'Created Vulkan swapchain' "$first_line" ||
        log_contains_since 'Selecting OpenGL shader profile' "$first_line"; then
      renderer_ready=1
    fi
    if [ "$renderer_ready" -eq 1 ] &&
        log_contains_since 'triad-subscription: connected' "$first_line" &&
        log_contains_since '^panel-created:' "$first_line"; then
      return 0
    fi
    process_is_running "$toasty_pid" || return 1
    process_is_running "$river_pid" ||
      fail "River exited while waiting for Toasty"
    process_is_running "$wayvnc_pid" ||
      fail "WayVNC exited while waiting for Toasty"
    attempts=$((attempts + 1))
    sleep 0.1
  done
  log_event "Toasty timed out during readiness checks"
  return 1
}

start_toasty() {
  rm -f -- "$log_dir/toasty.ready" "$log_dir/ready"
  if [ -f "$log_dir/toasty.log" ]; then
    previous_lines=$(wc -l <"$log_dir/toasty.log" | tr -d ' ')
  else
    previous_lines=0
  fi
  first_line=$((previous_lines + 1))

  log_event "starting Toasty (restart failures $toasty_failures/$restart_limit)"
  "$toasty_bin" >>"$log_dir/toasty.log" 2>&1 &
  toasty_pid=$!
  toasty_started_at=$(date +%s)
  printf '%s\n' "$toasty_pid" >"$log_dir/toasty.pid"

  if wait_for_toasty "$first_line"; then
    printf '%s\n' "$toasty_pid" >"$log_dir/toasty.ready"
    log_event "Toasty ready (pid $toasty_pid)"
    return 0
  fi

  toasty_status=0
  if process_is_running "$toasty_pid"; then
    terminate_process Toasty "$toasty_pid"
    toasty_status=1
  else
    wait "$toasty_pid" || toasty_status=$?
  fi
  rm -f -- "$log_dir/toasty.pid"
  log_event "Toasty failed readiness with status $toasty_status"
  return 1
}

start_toasty_bounded() {
  while ! start_toasty; do
    toasty_failures=$((toasty_failures + 1))
    if [ "$toasty_failures" -gt "$restart_limit" ]; then
      fail "Toasty exceeded the restart limit"
    fi
    sleep "$restart_delay"
  done
}

wait_for_wayvnc() {
  attempts=0
  while [ "$attempts" -lt "$startup_attempts" ]; do
    process_is_running "$wayvnc_pid" ||
      fail "WayVNC exited during startup"
    if nc -z "$vnc_address" "$vnc_port" 2>/dev/null; then
      return 0
    fi
    attempts=$((attempts + 1))
    sleep 0.1
  done
  fail "WayVNC did not listen on $vnc_address:$vnc_port"
}

write_ready_file() {
  {
    printf 'river_pid=%s\n' "$river_pid"
    printf 'wayvnc_pid=%s\n' "$wayvnc_pid"
    printf 'toasty_pid=%s\n' "$toasty_pid"
    printf 'wayland_display=%s\n' "$WAYLAND_DISPLAY"
    printf 'vnc_address=%s\n' "$vnc_address"
    printf 'vnc_port=%s\n' "$vnc_port"
  } >"$log_dir/ready"
}

monitor_session() {
  while :; do
    process_is_running "$river_pid" ||
      fail "River exited; inspect $log_dir/river.log"
    process_is_running "$wayvnc_pid" ||
      fail "WayVNC exited; inspect $log_dir/wayvnc.log"

    [ -f "$log_dir/triad-supervisor.pid" ] ||
      fail "the Triad supervisor exited"
    supervisor_pid=$(sed -n '1p' "$log_dir/triad-supervisor.pid")
    process_is_running "$supervisor_pid" ||
      fail "the Triad supervisor exited; inspect $log_dir/triad.log"

    if ! process_is_running "$toasty_pid"; then
      toasty_status=0
      wait "$toasty_pid" || toasty_status=$?
      rm -f -- "$log_dir/toasty.pid" "$log_dir/toasty.ready" "$log_dir/ready"
      stopped_at=$(date +%s)
      lifetime=$((stopped_at - toasty_started_at))
      if [ "$lifetime" -ge "$restart_reset" ]; then
        toasty_failures=0
      fi
      toasty_failures=$((toasty_failures + 1))
      log_event "Toasty exited with status $toasty_status after ${lifetime}s"
      if [ "$toasty_failures" -gt "$restart_limit" ]; then
        fail "Toasty exceeded the restart limit"
      fi
      sleep "$restart_delay"
      start_toasty_bounded
      write_ready_file
    fi
    sleep 0.2
  done
}

[ "$(uname -s)" = FreeBSD ] ||
  fail "the production session currently targets FreeBSD; found $(uname -s)"
is_unsigned_integer "$restart_limit" ||
  fail "TOASTY_SESSION_RESTART_LIMIT must be an unsigned integer"
is_unsigned_integer "$restart_reset" ||
  fail "TOASTY_SESSION_RESTART_RESET must be an unsigned integer"
is_unsigned_integer "$startup_attempts" ||
  fail "TOASTY_SESSION_STARTUP_ATTEMPTS must be an unsigned integer"
[ -x "$triad_bin" ] || fail "Triad binary is not executable: $triad_bin"
[ -f "$triad_config" ] || fail "Triad config is missing: $triad_config"
[ -x "$toasty_bin" ] || fail "Toasty binary is not executable: $toasty_bin"

river_bin=$(find_command "$river_bin")
wayvnc_bin=$(find_command "$wayvnc_bin")
wayland_info_bin=$(find_command "$wayland_info_bin")
find_command nc >/dev/null

umask 077
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
log_dir="$log_root/$timestamp-$$"
mkdir -p -- "$log_dir"
trap cleanup EXIT
trap stop_session INT TERM HUP

"$triad_bin" validate-config --config "$triad_config" \
  >"$log_dir/config-validation.log" 2>&1
stop_existing_session
ln -sfn -- "$log_dir" "$log_root/latest"
printf '%s\n' "$$" >"$log_dir/session.pid"

runtime_dir=$(mktemp -d "$runtime_base/toasty-session.XXXXXX")
chmod 700 "$runtime_dir"

export XDG_RUNTIME_DIR="$runtime_dir"
export XDG_CURRENT_DESKTOP=river
export XDG_SESSION_DESKTOP=toasty
export XDG_SESSION_TYPE=wayland
export NIMKIT_THEME=${NIMKIT_THEME:-DarkBSD}
export TRIAD_BIN="$triad_bin"
export TRIAD_CONFIG="$triad_config"
export TOASTY_SESSION_ACTIVE_LOG_DIR="$log_dir"
export TOASTY_SESSION_SCRIPT="$session_script"
export TOASTY_SESSION_RESTART_LIMIT="$restart_limit"
export TOASTY_SESSION_RESTART_DELAY="$restart_delay"
export TOASTY_SESSION_RESTART_RESET="$restart_reset"
export WLR_BACKENDS="$river_backends"
export WLR_RENDERER="$river_renderer"
if [ "$river_backends" = headless ]; then
  export WLR_HEADLESS_OUTPUTS="$headless_outputs"
else
  unset WLR_HEADLESS_OUTPUTS
fi
unset WAYLAND_DISPLAY

log_event "starting River"
"$river_bin" -log-level debug \
  -c 'exec "$TOASTY_SESSION_SCRIPT" triad-supervisor' \
  >"$log_dir/river.log" 2>&1 &
river_pid=$!
printf '%s\n' "$river_pid" >"$log_dir/river.pid"

wait_for_wayland_display
wait_for_file "$log_dir/triad-supervisor.pid" "$river_pid" River
wait_for_triad
log_event "River and Triad ready"

"$wayland_info_bin" >"$log_dir/wayland-info.log" 2>&1
require_protocol river_window_manager_v1 4
require_protocol river_xkb_bindings_v1 2
require_protocol wl_compositor 1
require_protocol wl_shm 1
require_protocol zwlr_layer_shell_v1 4

{
  printf 'date_utc=%s\n' "$timestamp"
  printf 'host=%s\n' "$(hostname)"
  printf 'os=%s\n' "$(uname -K)"
  printf 'river=%s\n' "$("$river_bin" -version 2>&1)"
  printf 'wayvnc=%s\n' "$("$wayvnc_bin" --version 2>&1 | head -n 1)"
  printf 'triad_commit=%s\n' "$(git -C "$default_triad_dir" rev-parse HEAD)"
  printf 'WAYLAND_DISPLAY=%s\n' "$WAYLAND_DISPLAY"
  printf 'XDG_RUNTIME_DIR=%s\n' "$XDG_RUNTIME_DIR"
  printf 'backend=%s\n' "$WLR_BACKENDS"
  printf 'renderer=%s\n' "$WLR_RENDERER"
  printf 'headless_outputs=%s\n' "${WLR_HEADLESS_OUTPUTS:-}"
  printf 'vnc_address=%s\n' "$vnc_address"
  printf 'vnc_port=%s\n' "$vnc_port"
  printf 'restart_limit=%s\n' "$restart_limit"
  printf 'restart_delay=%s\n' "$restart_delay"
  printf 'restart_reset=%s\n' "$restart_reset"
} >"$log_dir/environment.log"

log_event "starting WayVNC"
"$wayvnc_bin" --gpu "$vnc_address" "$vnc_port" \
  >"$log_dir/wayvnc.log" 2>&1 &
wayvnc_pid=$!
printf '%s\n' "$wayvnc_pid" >"$log_dir/wayvnc.pid"
wait_for_wayvnc
log_event "WayVNC ready (pid $wayvnc_pid)"

start_toasty_bounded
write_ready_file
log_event "session ready"

printf '%s\n' \
  "toasty-session: connect to $vnc_address:$vnc_port" \
  "toasty-session: logs: $log_dir"

if [ "$run_once" = 1 ]; then
  log_event "one-shot readiness check passed"
  exit 0
fi

monitor_session
