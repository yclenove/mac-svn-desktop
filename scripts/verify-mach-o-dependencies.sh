#!/usr/bin/env bash
# 校验一个 Mach-O 及其包内依赖的双架构、run-path 解析和应用边界。
set -euo pipefail

APP_PATH="${1:-}"
BINARY="${2:-}"
EXECUTABLE_DIRECTORY="${3:-}"
LABEL="${4:-Mach-O}"
REQUIRED_ARCHS="arm64 x86_64"
CHECKED_DEPENDENCY_BINARIES=$'\n'

if [[ -z "$APP_PATH" || -z "$BINARY" || -z "$EXECUTABLE_DIRECTORY" ]]; then
  echo "usage: $0 /path/to/App.app /path/to/binary /path/to/executable-directory [label]" >&2
  exit 2
fi

fail() { echo "verify-mach-o-dependencies: $*" >&2; exit 1; }

for command_name in lipo otool; do
  command -v "$command_name" >/dev/null 2>&1 || fail "缺少命令: $command_name"
done

[[ -d "$APP_PATH" ]] || fail "不是应用目录: $APP_PATH"
APP_CANONICAL="$(cd -P "$APP_PATH" && pwd)"

verify_architectures() {
  local binary="$1"
  local label="$2"
  local arch
  [[ -f "$binary" ]] || fail "$label 缺少 Mach-O 文件: $binary"
  for arch in $REQUIRED_ARCHS; do
    lipo "$binary" -verify_arch "$arch" >/dev/null \
      || fail "$label 缺少 $arch 架构: $binary"
  done
}

canonical_existing_path() {
  local path="$1"
  local directory
  local link_target

  [[ -e "$path" || -L "$path" ]] || return 1
  while true; do
    directory="$(cd -P "$(dirname "$path")" 2>/dev/null && pwd)" || return 1
    path="$directory/$(basename "$path")"
    if [[ ! -L "$path" ]]; then
      printf '%s\n' "$path"
      return 0
    fi
    link_target="$(readlink "$path")" || return 1
    if [[ "$link_target" == /* ]]; then
      path="$link_target"
    else
      path="$directory/$link_target"
    fi
  done
}

binary_rpaths() {
  otool -l "$1" | /usr/bin/awk '
    $1 == "cmd" && $2 == "LC_RPATH" { capture = 1; next }
    capture && $1 == "path" {
      line = $0
      sub(/^[[:space:]]*path[[:space:]]+/, "", line)
      sub(/[[:space:]]+\(offset[[:space:]][0-9]+\)[[:space:]]*$/, "", line)
      print line
      capture = 0
    }
  '
}

expand_runtime_path() {
  local value="$1"
  local loader_directory="$2"
  local executable_directory="$3"
  case "$value" in
    @loader_path) printf '%s\n' "$loader_directory" ;;
    @loader_path/*) printf '%s/%s\n' "$loader_directory" "${value#@loader_path/}" ;;
    @executable_path) printf '%s\n' "$executable_directory" ;;
    @executable_path/*) printf '%s/%s\n' "$executable_directory" "${value#@executable_path/}" ;;
    /*) printf '%s\n' "$value" ;;
    *) return 1 ;;
  esac
}

resolve_embedded_dependency() {
  local dependency="$1"
  local binary="$2"
  local executable_directory="$3"
  local search_rpaths="$4"
  local loader_directory
  local candidate=""
  local canonical_candidate
  local rpath

  loader_directory="$(dirname "$binary")"
  case "$dependency" in
    @loader_path/*)
      candidate="$loader_directory/${dependency#@loader_path/}"
      ;;
    @executable_path/*)
      candidate="$executable_directory/${dependency#@executable_path/}"
      ;;
    @rpath/*)
      while IFS= read -r rpath; do
        [[ -n "$rpath" ]] || continue
        candidate="$rpath/${dependency#@rpath/}"
        if [[ -e "$candidate" || -L "$candidate" ]]; then
          break
        fi
        candidate=""
      done <<< "$search_rpaths"
      ;;
    *)
      fail "不允许的动态依赖: $dependency"
      ;;
  esac

  [[ -n "$candidate" ]] || fail "依赖无法解析到应用包内: ${dependency}（加载者: ${binary}）"
  canonical_candidate="$(canonical_existing_path "$candidate" 2>/dev/null || true)"
  [[ -n "$canonical_candidate" && -f "$canonical_candidate" ]] \
    || fail "依赖无法解析到应用包内: ${dependency}（候选: ${candidate}）"
  case "$canonical_candidate" in
    "$APP_CANONICAL"/Contents/*) ;;
    *) fail "依赖越过应用包边界: $dependency -> $canonical_candidate" ;;
  esac
  printf '%s\n' "$canonical_candidate"
}

verify_dependencies() {
  local binary="$1"
  local label="$2"
  local executable_directory="$3"
  local inherited_rpaths="${4:-}"
  local canonical_binary
  local dependency
  local dependency_line
  local resolved_dependency
  local rpath
  local expanded_rpath
  local search_rpaths=$'\n'
  local visit_key

  canonical_binary="$(canonical_existing_path "$binary")" \
    || fail "$label 无法解析 Mach-O 文件: $binary"
  while IFS= read -r rpath; do
    [[ -n "$rpath" ]] || continue
    expanded_rpath="$(expand_runtime_path "$rpath" "$(dirname "$canonical_binary")" "$executable_directory" 2>/dev/null || true)"
    [[ -n "$expanded_rpath" ]] || continue
    case "$search_rpaths" in
      *$'\n'"$expanded_rpath"$'\n'*) ;;
      *) search_rpaths="${search_rpaths}${expanded_rpath}"$'\n' ;;
    esac
  done < <(binary_rpaths "$canonical_binary")
  while IFS= read -r rpath; do
    [[ -n "$rpath" ]] || continue
    case "$search_rpaths" in
      *$'\n'"$rpath"$'\n'*) ;;
      *) search_rpaths="${search_rpaths}${rpath}"$'\n' ;;
    esac
  done <<< "$inherited_rpaths"

  visit_key="$canonical_binary|$executable_directory|$(printf '%s' "$search_rpaths" | /usr/bin/cksum)"
  case "$CHECKED_DEPENDENCY_BINARIES" in
    *$'\n'"$visit_key"$'\n'*) return 0 ;;
  esac
  CHECKED_DEPENDENCY_BINARIES="${CHECKED_DEPENDENCY_BINARIES}${visit_key}"$'\n'

  while IFS= read -r dependency_line; do
    [[ "$dependency_line" == *: ]] && continue
    dependency="$(/usr/bin/sed -E 's/^[[:space:]]+//; s/[[:space:]]+\(compatibility version.*$//' <<< "$dependency_line")"
    [[ -n "$dependency" ]] || continue
    case "$dependency" in
      /System/Library/*|/usr/lib/*) ;;
      @rpath/*|@loader_path/*|@executable_path/*)
        resolved_dependency="$(resolve_embedded_dependency "$dependency" "$canonical_binary" "$executable_directory" "$search_rpaths")"
        verify_architectures "$resolved_dependency" "$label 的包内依赖"
        verify_dependencies "$resolved_dependency" "$label 的包内依赖" "$executable_directory" "$search_rpaths"
        ;;
      *) fail "$label 存在不允许的动态依赖: $dependency" ;;
    esac
  done < <(otool -L "$canonical_binary" | /usr/bin/tail -n +2)
}

verify_architectures "$BINARY" "$LABEL"
verify_dependencies "$BINARY" "$LABEL" "$EXECUTABLE_DIRECTORY" $'\n'
echo "verify-mach-o-dependencies: OK ($LABEL; archs=$REQUIRED_ARCHS)"
