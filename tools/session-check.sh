#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
session_script="$project_dir/tools/session.sh"
state_home=${XDG_STATE_HOME:-"$HOME/.local/state"}
check_root=${TOASTY_SESSION_CHECK_LOG_DIR:-"$state_home/toasty/session-check"}
startup_attempts=${TOASTY_SESSION_STARTUP_ATTEMPTS:-200}

session_pid=
active_dir=
cleaned=0

fail() {
  printf 'session-check: %s\n' "$*" >&2
  exit 1
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

cleanup() {
  [ "$cleaned" -eq 0 ] || return
  cleaned=1
  trap - EXIT INT TERM HUP
  if [ -n "$session_pid" ] && process_is_running "$session_pid"; then
    kill "$session_pid" 2>/dev/null || true
  fi
  if [ -n "$session_pid" ]; then
    wait "$session_pid" 2>/dev/null || true
  fi
}

stop_check() {
  cleanup
  exit 130
}

wait_for_file() {
  waited_path=$1
  attempts=0
  while [ "$attempts" -lt "$startup_attempts" ]; do
    [ -f "$waited_path" ] && return 0
    process_is_running "$session_pid" ||
      fail "the session exited while waiting for $waited_path"
    attempts=$((attempts + 1))
    sleep 0.1
  done
  fail "timed out waiting for $waited_path"
}

read_pid() {
  sed -n '1p' "$1"
}

wait_for_new_pid() {
  pid_path=$1
  previous_pid=$2
  attempts=0
  while [ "$attempts" -lt "$startup_attempts" ]; do
    if [ -f "$pid_path" ]; then
      current_pid=$(read_pid "$pid_path")
      if [ -n "$current_pid" ] &&
          [ "$current_pid" != "$previous_pid" ] &&
          process_is_running "$current_pid"; then
        printf '%s\n' "$current_pid"
        return 0
      fi
    fi
    process_is_running "$session_pid" ||
      fail "the session exited while waiting for a component restart"
    attempts=$((attempts + 1))
    sleep 0.1
  done
  fail "timed out waiting for a new PID in $pid_path"
}

wait_for_more_connections() {
  previous_count=$1
  attempts=0
  while [ "$attempts" -lt "$startup_attempts" ]; do
    current_count=$(grep -c 'triad-subscription: connected' \
      "$active_dir/toasty.log" 2>/dev/null || true)
    if [ "$current_count" -gt "$previous_count" ]; then
      return 0
    fi
    process_is_running "$session_pid" ||
      fail "the session exited while waiting for Toasty to reconnect"
    attempts=$((attempts + 1))
    sleep 0.1
  done
  fail "Toasty did not reconnect after the Triad restart"
}

assert_stable_pid() {
  label=$1
  pid_path=$2
  expected_pid=$3
  actual_pid=$(read_pid "$pid_path")
  [ "$actual_pid" = "$expected_pid" ] ||
    fail "$label changed from PID $expected_pid to $actual_pid"
  process_is_running "$actual_pid" ||
    fail "$label PID $actual_pid is not running"
}

[ "$(uname -s)" = FreeBSD ] ||
  fail "the integration check currently targets FreeBSD"

umask 077
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
check_dir="$check_root/$timestamp-$$"
session_log_root="$check_dir/session"
mkdir -p -- "$check_dir"
ln -sfn -- "$check_dir" "$check_root/latest"
trap cleanup EXIT
trap stop_check INT TERM HUP

TOASTY_SESSION_LOG_DIR="$session_log_root" \
  "$session_script" >"$check_dir/supervisor.log" 2>&1 &
session_pid=$!

wait_for_file "$session_log_root/latest/ready"
active_dir=$(CDPATH= cd -- "$session_log_root/latest" && pwd)

river_pid=$(read_pid "$active_dir/river.pid")
wayvnc_pid=$(read_pid "$active_dir/wayvnc.pid")
triad_pid=$(read_pid "$active_dir/triad.pid")
toasty_pid=$(read_pid "$active_dir/toasty.pid")
dbus_pid=
if [ -f "$active_dir/dbus.pid" ]; then
  dbus_pid=$(read_pid "$active_dir/dbus.pid")
fi

connections_before=$(grep -c 'triad-subscription: connected' \
  "$active_dir/toasty.log")
kill "$triad_pid"
new_triad_pid=$(wait_for_new_pid "$active_dir/triad.pid" "$triad_pid")
wait_for_more_connections "$connections_before"
assert_stable_pid River "$active_dir/river.pid" "$river_pid"
assert_stable_pid WayVNC "$active_dir/wayvnc.pid" "$wayvnc_pid"
if [ -n "$dbus_pid" ]; then
  assert_stable_pid D-Bus "$active_dir/dbus.pid" "$dbus_pid"
fi

kill "$toasty_pid"
new_toasty_pid=$(wait_for_new_pid "$active_dir/toasty.pid" "$toasty_pid")
wait_for_file "$active_dir/toasty.ready"
ready_toasty_pid=$(read_pid "$active_dir/toasty.ready")
[ "$ready_toasty_pid" = "$new_toasty_pid" ] ||
  fail "Toasty PID changed before completing readiness"
assert_stable_pid River "$active_dir/river.pid" "$river_pid"
assert_stable_pid WayVNC "$active_dir/wayvnc.pid" "$wayvnc_pid"
if [ -n "$dbus_pid" ]; then
  assert_stable_pid D-Bus "$active_dir/dbus.pid" "$dbus_pid"
fi

kill "$session_pid"
session_status=0
wait "$session_pid" || session_status=$?
session_pid=
[ "$session_status" -eq 0 ] ||
  fail "the supervisor returned status $session_status during shutdown"

for stopped_pid in \
  "$river_pid" "$wayvnc_pid" "$new_triad_pid" "$new_toasty_pid" $dbus_pid; do
  process_is_running "$stopped_pid" &&
    fail "component PID $stopped_pid survived session shutdown"
done

trap - EXIT INT TERM HUP
cleaned=1
printf '%s\n' \
  "session-check: Triad restarted $triad_pid -> $new_triad_pid" \
  "session-check: Toasty restarted $toasty_pid -> $new_toasty_pid" \
  "session-check: River and WayVNC stayed at $river_pid and $wayvnc_pid" \
  "session-check: the D-Bus notification bus stayed at ${dbus_pid:-external}" \
  "session-check: clean signal shutdown passed" \
  "session-check: logs: $check_dir"
