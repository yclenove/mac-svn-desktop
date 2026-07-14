#!/usr/bin/env bash
# 在隔离用户目录与最小 PATH 下真实启动应用，确认不会依赖开发环境才能存活。
set -euo pipefail

APP_PATH="${1:-}"
STABILITY_SECONDS="${SVNSTUDIO_SMOKE_STABILITY_SECONDS:-5}"
TERMINATION_GRACE_SECONDS="${SVNSTUDIO_SMOKE_TERMINATION_GRACE_SECONDS:-2}"

if [[ -z "$APP_PATH" ]]; then
  echo "usage: $0 /path/to/SVNStudio.app" >&2
  exit 2
fi

fail() { echo "smoke-test-macos-app: $*" >&2; exit 1; }

case "$STABILITY_SECONDS" in
  ''|*[!0-9]*|0) fail "稳定性窗口必须是正整数秒: $STABILITY_SECONDS" ;;
esac
case "$TERMINATION_GRACE_SECONDS" in
  ''|*[!0-9]*|0) fail "终止宽限期必须是正整数秒: $TERMINATION_GRACE_SECONDS" ;;
esac

PLIST="$APP_PATH/Contents/Info.plist"
[[ -f "$PLIST" ]] || fail "缺少 Info.plist: $PLIST"
EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST" 2>/dev/null || true)"
[[ -n "$EXECUTABLE" ]] || fail "无法读取 CFBundleExecutable"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/$EXECUTABLE"
[[ -x "$EXECUTABLE_PATH" ]] || fail "主应用不可执行: $EXECUTABLE_PATH"

OWNS_SMOKE_HOME=0
if [[ -n "${SVNSTUDIO_SMOKE_HOME:-}" ]]; then
  SMOKE_HOME="$SVNSTUDIO_SMOKE_HOME"
  mkdir -p "$SMOKE_HOME"
else
  SMOKE_HOME="$(mktemp -d /tmp/svnstudio-release-smoke.XXXXXX)"
  OWNS_SMOKE_HOME=1
fi
SMOKE_HOME="$(cd "$SMOKE_HOME" && pwd -P)"
SMOKE_TMP="$SMOKE_HOME/tmp"
SMOKE_LOG="${SVNSTUDIO_SMOKE_LOG_PATH:-$SMOKE_HOME/SVNStudio-smoke.log}"
mkdir -p "$SMOKE_TMP"
APP_PID=""
APP_PGID=""

process_group_is_running() {
  local pid
  local state
  [[ -n "$APP_PGID" ]] || return 1
  for pid in $(/usr/bin/pgrep -g "$APP_PGID" 2>/dev/null || true); do
    state="$(/bin/ps -o state= -p "$pid" 2>/dev/null | /usr/bin/tr -d ' ')"
    if [[ -n "$state" && "$state" != Z* ]]; then
      return 0
    fi
  done
  return 1
}

terminate_app() {
  local attempt
  [[ -n "$APP_PID" ]] || return 0

  /bin/kill -TERM "-$APP_PGID" 2>/dev/null || true

  for ((attempt = 0; attempt < TERMINATION_GRACE_SECONDS * 10; attempt += 1)); do
    process_group_is_running || break
    sleep 0.1
  done

  if process_group_is_running; then
    echo "smoke-test-macos-app: 进程树未在 ${TERMINATION_GRACE_SECONDS}s 内退出，升级 SIGKILL" >&2
    /bin/kill -KILL "-$APP_PGID" 2>/dev/null || true
  fi
  wait "$APP_PID" 2>/dev/null || true
  APP_PID=""
  APP_PGID=""
}

cleanup() {
  terminate_app
  if [[ "$OWNS_SMOKE_HOME" == "1" ]]; then
    rm -rf "$SMOKE_HOME"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

FOUNDATION_HOME="$(
  HOME="$SMOKE_HOME" CFFIXED_USER_HOME="$SMOKE_HOME" \
    /usr/bin/osascript -l JavaScript \
      -e 'ObjC.import("Foundation"); ObjC.unwrap($.NSHomeDirectory())'
)" || fail "无法验证 Foundation 用户目录"
FOUNDATION_HOME="$(cd "$FOUNDATION_HOME" 2>/dev/null && pwd -P)" \
  || fail "Foundation 用户目录不可访问: $FOUNDATION_HOME"
[[ "$FOUNDATION_HOME" == "$SMOKE_HOME" ]] \
  || fail "Foundation 用户目录未隔离: $FOUNDATION_HOME"

set -m
HOME="$SMOKE_HOME" CFFIXED_USER_HOME="$SMOKE_HOME" TMPDIR="$SMOKE_TMP" PATH=/usr/bin:/bin \
  "$EXECUTABLE_PATH" >"$SMOKE_LOG" 2>&1 &
APP_PID=$!
APP_PGID="$(/bin/ps -o pgid= -p "$APP_PID" 2>/dev/null | /usr/bin/tr -d ' ')"
set +m
[[ "$APP_PGID" == "$APP_PID" ]] || fail "无法为冒烟应用建立独立进程组"

for ((second = 0; second < STABILITY_SECONDS; second += 1)); do
  sleep 1
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    wait "$APP_PID" 2>/dev/null || true
    APP_PID=""
    APP_PGID=""
    /usr/bin/sed -n '1,160p' "$SMOKE_LOG" >&2
    fail "应用在稳定性窗口内提前退出"
  fi
done

if /usr/bin/grep -Eq 'Fatal error|Assertion failed|abort\(' "$SMOKE_LOG"; then
  /usr/bin/sed -n '1,160p' "$SMOKE_LOG" >&2
  fail "启动日志包含致命错误"
fi

terminate_app
echo "smoke-test-macos-app: 启动稳定性冒烟通过 ($APP_PATH; isolated-home=$SMOKE_HOME)"
