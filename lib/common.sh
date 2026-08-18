#!/usr/bin/env bash
#
# common.sh: logging, guards, and shared paths.
#
# Sourced by lib/steps.sh and the `winmac` entrypoint. Never run directly.

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
WINMAC_ROOT="${WINMAC_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
GAMES_DIR="$WINMAC_ROOT/games"

# The Wine prefix every game shares. One prefix keeps a single Steam install
# and a single login, which is what you want: Steam refuses to run twice.
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-steam}"

# Upstream project that builds the Wine 11 + Steam + steamwebhelper-wrapper
# stack. We do not reimplement it; we clone it and drive it, then layer the
# per-game renderer work on top.
UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/notpop/steam-on-m1-wine.git}"
UPSTREAM_DIR="${UPSTREAM_DIR:-$HOME/steam-on-m1-wine}"

WINE_BIN="${WINE_BIN:-/opt/homebrew/bin/wine}"
WINESERVER_BIN="${WINESERVER_BIN:-/opt/homebrew/bin/wineserver}"

STEAM_DIR_WIN="C:\\Program Files (x86)\\Steam"
STEAM_DIR_UNIX="$WINEPREFIX/drive_c/Program Files (x86)/Steam"
STEAMAPPS="$STEAM_DIR_UNIX/steamapps"

# Mesa for Windows. Supplies a real opengl32.dll when Wine's macOS OpenGL
# driver cannot create a context. See docs/renderers.md.
MESA_VERSION="${MESA_VERSION:-26.2.0}"
MESA_URL="https://github.com/pal1000/mesa-dist-win/releases/download/${MESA_VERSION}/mesa3d-${MESA_VERSION}-release-msvc.7z"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    _C_RESET=$'\033[0m'; _C_DIM=$'\033[2m'; _C_RED=$'\033[31m'
    _C_GREEN=$'\033[32m'; _C_YELLOW=$'\033[33m'; _C_BOLD=$'\033[1m'
else
    _C_RESET=""; _C_DIM=""; _C_RED=""; _C_GREEN=""; _C_YELLOW=""; _C_BOLD=""
fi

_ts() { date '+%H:%M:%S'; }

log_step() { printf '\n%s== %s ==%s\n' "$_C_BOLD" "$*" "$_C_RESET"; }
log_info() { printf '%s%s%s %s\n' "$_C_DIM" "$(_ts)" "$_C_RESET" "$*"; }
log_ok()   { printf '%s%s%s %s[ok]%s %s\n' "$_C_DIM" "$(_ts)" "$_C_RESET" "$_C_GREEN" "$_C_RESET" "$*"; }
log_warn() { printf '%s%s%s %s[warn]%s %s\n' "$_C_DIM" "$(_ts)" "$_C_RESET" "$_C_YELLOW" "$_C_RESET" "$*" >&2; }
log_err()  { printf '%s%s%s %s[error]%s %s\n' "$_C_DIM" "$(_ts)" "$_C_RESET" "$_C_RED" "$_C_RESET" "$*" >&2; }
die()      { log_err "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------
require_macos_arm64() {
    [[ "$(uname -s)" == "Darwin" ]] || die "macOS only (found $(uname -s))."
    [[ "$(uname -m)" == "arm64" ]] || die "Apple Silicon only (found $(uname -m))."
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 \
        || die "Missing required command: $1${2:+ ($2)}"
}

require_prefix() {
    [[ -d "$WINEPREFIX" ]] \
        || die "No Wine prefix at $WINEPREFIX. Run: winmac setup"
    [[ -f "$STEAM_DIR_UNIX/Steam.exe" ]] \
        || die "Steam not installed in prefix. Run: winmac setup"
}

# Kill everything in the prefix. Steam's single-instance guard and Chromium's
# lock files both misbehave if a previous session is still half-alive.
kill_prefix() {
    pkill -9 -f "Mewgenics.exe" 2>/dev/null || true
    pkill -9 -f "winedbg" 2>/dev/null || true
    pkill -9 -f "steamwebhelper" 2>/dev/null || true
    pkill -9 -f "Steam.exe" 2>/dev/null || true
    [[ -n "${GAME_EXE:-}" ]] && pkill -9 -f "$GAME_EXE" 2>/dev/null || true
    sleep 2
    "$WINESERVER_BIN" -k9 2>/dev/null || true
    sleep 2
}

# Wine's registry, per-application scope.
#   wine_reg_app <exe> <subkey-or-empty> <value> <data>
# A per-app override is essential: setting opengl32=native prefix-wide breaks
# Steam itself with a "Could not load module 'bin/vgui2_s.dll'" fatal error.
wine_reg_app() {
    local exe="$1" subkey="$2" name="$3" data="$4"
    local key="HKCU\\Software\\Wine\\AppDefaults\\${exe}"
    [[ -n "$subkey" ]] && key="${key}\\${subkey}"
    WINEDEBUG=-all "$WINE_BIN" reg add "$key" /v "$name" /d "$data" /f >/dev/null 2>&1 \
        || die "Failed to write registry key $key"
}
