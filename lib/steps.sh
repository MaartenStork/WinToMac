#!/usr/bin/env bash
#
# steps.sh — the pipeline stages.
#
# Sourced by the `winmac` entrypoint. Never run directly.

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

# load_game <name> — source games/<name>.conf and validate it.
load_game() {
    local name="${1:-}"
    [[ -n "$name" ]] || die "No game given. Try: winmac list"

    local conf="$GAMES_DIR/${name%.conf}.conf"
    [[ -f "$conf" ]] || die "No config at $conf. Copy games/EXAMPLE.conf and edit it."

    # Defaults, so a minimal config still works.
    GAME_NAME=""; STEAM_APPID=""; STEAM_DEPOTID=""; STEAM_MANIFESTID=""
    GAME_DIR=""; GAME_EXE=""; RENDERER="auto"; WINDOWS_VERSION=""
    LP_THREADS=""; EXTRA_ENV=()

    # shellcheck disable=SC1090
    source "$conf"

    GAME_CONF="$conf"
    GAME_SLUG="${name%.conf}"

    local missing=()
    [[ -n "$GAME_NAME"   ]] || missing+=("GAME_NAME")
    [[ -n "$STEAM_APPID" ]] || missing+=("STEAM_APPID")
    [[ -n "$GAME_DIR"    ]] || missing+=("GAME_DIR")
    [[ -n "$GAME_EXE"    ]] || missing+=("GAME_EXE")
    (( ${#missing[@]} == 0 )) \
        || die "$conf is missing: ${missing[*]}"

    GAME_PATH="$STEAMAPPS/common/$GAME_DIR"
    GAME_EXE_PATH="$GAME_PATH/$GAME_EXE"

    # Physical cores minus a couple, so audio and OS threads keep headroom.
    # Software rendering saturates every core it is given, and starved audio
    # buffers are the usual cause of crackling.
    if [[ -z "$LP_THREADS" ]]; then
        LP_THREADS="$(sysctl -n hw.perflevel0.logicalcpu 2>/dev/null || echo 4)"
    fi
}

list_games() {
    log_step "Configured games"
    local found=0
    for f in "$GAMES_DIR"/*.conf; do
        [[ -e "$f" ]] || continue
        local b; b="$(basename "$f" .conf)"
        [[ "$b" == "EXAMPLE" ]] && continue
        local nm appid
        nm="$(grep -m1 '^GAME_NAME=' "$f" | cut -d'"' -f2)"
        appid="$(grep -m1 '^STEAM_APPID=' "$f" | cut -d= -f2 | tr -d '" ')"
        printf '  %-24s %s (app %s)\n' "$b" "${nm:-?}" "${appid:-?}"
        found=1
    done
    (( found )) || log_info "None yet. Copy games/EXAMPLE.conf to games/<name>.conf"
}

# ---------------------------------------------------------------------------
# doctor
# ---------------------------------------------------------------------------
step_doctor() {
    log_step "Environment"
    require_macos_arm64
    log_ok "macOS $(sw_vers -productVersion) on $(sysctl -n machdep.cpu.brand_string)"

    local free_gb; free_gb="$(df -g / | tail -1 | awk '{print $4}')"
    if (( free_gb < 15 )); then
        log_warn "Only ${free_gb} GB free. A Steam install plus one game wants 15 GB+."
    else
        log_ok "${free_gb} GB free"
    fi

    command -v brew >/dev/null && log_ok "Homebrew $(brew --version | head -1 | awk '{print $2}')" \
                               || log_warn "Homebrew not found — required by setup"

    if [[ -x "$WINE_BIN" ]]; then
        log_ok "Wine: $("$WINE_BIN" --version 2>/dev/null || echo unknown)"
    else
        log_warn "Wine not installed yet — run: winmac setup"
    fi

    [[ -d "$WINEPREFIX" ]] && log_ok "Prefix: $WINEPREFIX" \
                           || log_warn "No prefix yet — run: winmac setup"
    [[ -f "$STEAM_DIR_UNIX/Steam.exe" ]] && log_ok "Steam installed in prefix" \
                                         || log_warn "Steam not in prefix yet"

    # The stack depends on a Homebrew cask Homebrew has deprecated.
    if command -v brew >/dev/null && brew info --cask wine-stable 2>/dev/null | grep -qi deprecated; then
        log_warn "Homebrew's wine-stable cask is deprecated (Gatekeeper). Existing"
        log_warn "installs keep working, but a fresh 'brew install' may fail."
        log_warn "Do not delete /Applications/Wine Stable.app once it works."
    fi
}

# ---------------------------------------------------------------------------
# setup — Wine 11 + Steam + steamwebhelper wrapper, via upstream
# ---------------------------------------------------------------------------
step_setup() {
    require_macos_arm64
    require_cmd git
    require_cmd brew "install from https://brew.sh"

    log_step "Wine + Steam stack"
    log_info "This delegates to notpop/steam-on-m1-wine, which builds the"
    log_info "Wine 11 prefix, installs Steam, and installs a steamwebhelper"
    log_info "wrapper that forces CEF to --disable-gpu --single-process."
    log_info "Without that wrapper, modern Steam cannot render its own UI."

    if [[ -d "$UPSTREAM_DIR/.git" ]]; then
        log_ok "Upstream already cloned at $UPSTREAM_DIR"
    else
        log_info "Cloning upstream to $UPSTREAM_DIR"
        git clone --depth 1 "$UPSTREAM_REPO" "$UPSTREAM_DIR" \
            || die "Clone failed"
    fi

    log_warn "The installer needs your password (Wine ships as a .pkg)."
    log_warn "Run this yourself, then re-run 'winmac setup' to continue:"
    printf '\n    cd %s && bash install.sh --minimal\n\n' "$UPSTREAM_DIR"
    log_info "Use --minimal. The full build compiles LLVM and DXMT for D3D11"
    log_info "games; it takes an hour and does nothing for OpenGL titles."

    if [[ -f "$STEAM_DIR_UNIX/Steam.exe" ]]; then
        log_ok "Steam is present — setup looks complete"
    else
        log_warn "Steam not detected in the prefix yet."
        log_info "Note: upstream's wrapper step fails the first time, because"
        log_info "Steam only downloads its CEF files on first run. Launch Steam"
        log_info "once, quit it, then run install.sh again. See docs/troubleshooting.md"
        return 1
    fi

    _patch_upstream_launcher
}

# Inject our renderer environment into upstream's launcher so that every
# launch path (including its generated .app) picks it up.
_patch_upstream_launcher() {
    local ls="$UPSTREAM_DIR/scripts/launch-steam.sh"
    [[ -f "$ls" ]] || { log_warn "Upstream launcher not found; skipping patch"; return 0; }

    if grep -q "WINMAC_ENV_BLOCK" "$ls"; then
        log_ok "Upstream launcher already patched"
        return 0
    fi

    # Append after upstream's own WINEDLLOVERRIDES export.
    python3 - "$ls" <<'PYEOF'
import sys, re
path = sys.argv[1]
src = open(path).read()
marker = 'export WINEDLLOVERRIDES="dxgi'
i = src.find(marker)
if i == -1:
    sys.exit(0)
eol = src.find('\n', i) + 1
block = '''
# --- WINMAC_ENV_BLOCK (managed by winmac; safe to delete) ------------------
# Renderer environment for the game being launched. winmac writes these
# defaults; override any of them on the command line to experiment.
: "${GALLIUM_DRIVER:=}"
: "${LIBGL_ALWAYS_SOFTWARE:=}"
[[ -n "$GALLIUM_DRIVER" ]] && export GALLIUM_DRIVER
[[ -n "$LIBGL_ALWAYS_SOFTWARE" ]] && export LIBGL_ALWAYS_SOFTWARE
[[ -n "${LP_NUM_THREADS:-}" ]] && export LP_NUM_THREADS
[[ -n "${mesa_glthread:-}" ]] && export mesa_glthread
[[ -n "${MESA_GL_VERSION_OVERRIDE:-}" ]] && export MESA_GL_VERSION_OVERRIDE
[[ -n "${MESA_GLSL_VERSION_OVERRIDE:-}" ]] && export MESA_GLSL_VERSION_OVERRIDE
[[ -n "${SDL_RENDER_DRIVER:-}" ]] && export SDL_RENDER_DRIVER
# --- end WINMAC_ENV_BLOCK --------------------------------------------------
'''
open(path, 'w').write(src[:eol] + block + src[eol:])
PYEOF
    bash -n "$ls" || die "Patched launcher has a syntax error; revert with git -C $UPSTREAM_DIR checkout ."
    log_ok "Patched upstream launcher to honour winmac's renderer environment"
}

# ---------------------------------------------------------------------------
# fetch — download the Windows depot on macOS
# ---------------------------------------------------------------------------
step_fetch() {
    require_prefix

    log_step "Fetching $GAME_NAME"

    if [[ -f "$GAME_EXE_PATH" ]]; then
        log_ok "Already installed: $GAME_EXE_PATH"
        return 0
    fi

    if [[ -z "$STEAM_DEPOTID" || -z "$STEAM_MANIFESTID" ]]; then
        log_err "STEAM_DEPOTID and STEAM_MANIFESTID are not set in $GAME_CONF"
        log_info "See docs/finding-ids.md — SteamDB lists both, and an existing"
        log_info "appmanifest_${STEAM_APPID}.acf contains them too."
        return 1
    fi

    cat <<EOF

  Steam refuses to install a Windows-only game on macOS. Naming the depot
  and manifest explicitly skips that check entirely.

  1. Open your NORMAL macOS Steam app (not the one in the prefix).
  2. Run:  open "steam://open/console"
  3. Paste this into the Console tab:

       download_depot $STEAM_APPID $STEAM_DEPOTID $STEAM_MANIFESTID

  It is single-threaded and prints almost nothing, so expect it to be slow
  and quiet. It finishes with "Depot download complete".

  Then re-run:  winmac fetch $GAME_SLUG

EOF

    local content="$HOME/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/steamapps/content/app_${STEAM_APPID}/depot_${STEAM_DEPOTID}"
    if [[ -d "$content" ]] && [[ -n "$(ls -A "$content" 2>/dev/null)" ]]; then
        log_ok "Found downloaded depot at:"
        log_info "  $content"
        mkdir -p "$GAME_PATH"
        log_info "Moving into the prefix (same volume, so instant)"
        mv "$content"/* "$GAME_PATH"/ || die "Move failed"
        rm -rf "$(dirname "$content")"
        _write_appmanifest
        log_ok "Installed to $GAME_PATH"
    else
        log_warn "Depot not downloaded yet. Follow the steps above."
        log_info "Note: download_depot writes inside the Steam .app bundle,"
        log_info "not your Steam library folder. winmac knows where to look."
        return 1
    fi
}

# Steam only treats a game as installed if an appmanifest says so.
_write_appmanifest() {
    local size; size=$(find "$GAME_PATH" -type f -exec stat -f "%z" {} \; | awk '{s+=$1} END {print s+0}')
    cat > "$STEAMAPPS/appmanifest_${STEAM_APPID}.acf" <<EOF
"AppState"
{
	"appid"		"$STEAM_APPID"
	"Universe"		"1"
	"name"		"$GAME_NAME"
	"StateFlags"		"4"
	"installdir"		"$GAME_DIR"
	"LastUpdated"		"$(date +%s)"
	"SizeOnDisk"		"$size"
	"StagingSize"		"0"
	"buildid"		"0"
	"AutoUpdateBehavior"		"1"
	"InstalledDepots"
	{
		"$STEAM_DEPOTID"
		{
			"manifest"		"$STEAM_MANIFESTID"
			"size"		"$size"
		}
	}
	"UserConfig"
	{
		"language"		"english"
	}
}
EOF
    log_ok "Wrote appmanifest_${STEAM_APPID}.acf (StateFlags=4, installed)"
}

# ---------------------------------------------------------------------------
# install — renderer fixes and per-app overrides
# ---------------------------------------------------------------------------
step_install() {
    require_prefix
    [[ -f "$GAME_EXE_PATH" ]] || die "$GAME_EXE not found. Run: winmac fetch $GAME_SLUG"

    log_step "Configuring $GAME_NAME"

    if [[ -n "$WINDOWS_VERSION" ]]; then
        wine_reg_app "$GAME_EXE" "" "Version" "$WINDOWS_VERSION"
        log_ok "Windows version for $GAME_EXE set to $WINDOWS_VERSION"
    fi

    case "$RENDERER" in
        mesa-llvmpipe|mesa-zink|auto) _install_mesa ;;
        dxmt)   log_ok "Using DXMT (D3D11 to Metal); upstream installs it already" ;;
        native) log_ok "Using Wine's own OpenGL — no override installed" ;;
        *)      die "Unknown RENDERER '$RENDERER' in $GAME_CONF" ;;
    esac

    log_ok "Configured. Launch with: winmac launch $GAME_SLUG"
}

# Install Mesa's opengl32 beside the game and override it FOR THIS EXE ONLY.
_install_mesa() {
    require_cmd curl
    local sevenzip
    sevenzip="$(command -v 7z || command -v 7za || true)"
    [[ -n "$sevenzip" ]] || die "7z not found. Install with: brew install p7zip"

    if [[ -f "$GAME_PATH/libgallium_wgl.dll" ]]; then
        log_ok "Mesa already installed beside the game"
    else
        local tmp; tmp="$(mktemp -d)"
        log_info "Downloading mesa-dist-win $MESA_VERSION"
        curl -fL --retry 3 -o "$tmp/mesa.7z" "$MESA_URL" || die "Mesa download failed"
        "$sevenzip" x -y -o"$tmp/mesa" "$tmp/mesa.7z" >/dev/null || die "Extract failed"
        cp "$tmp/mesa/x64/opengl32.dll" "$tmp/mesa/x64/libgallium_wgl.dll" \
           "$tmp/mesa/x64/dxil.dll" "$GAME_PATH/" || die "Copy failed"
        rm -rf "$tmp"
        log_ok "Installed Mesa opengl32.dll + libgallium_wgl.dll into $GAME_DIR"
    fi

    # The critical detail. Prefix-wide (`WINEDLLOVERRIDES=opengl32=n`) makes
    # Steam itself load Mesa's DLL, which it cannot find, and Steam dies with
    # "Could not load module 'bin/vgui2_s.dll'". Scope it to the game.
    wine_reg_app "$GAME_EXE" "DllOverrides" "opengl32" "native"
    log_ok "Per-app override: $GAME_EXE loads Mesa's opengl32 (Steam does not)"
}

# ---------------------------------------------------------------------------
# launch
# ---------------------------------------------------------------------------
_renderer_env() {
    case "$RENDERER" in
        mesa-llvmpipe|auto)
            export GALLIUM_DRIVER=llvmpipe
            export LIBGL_ALWAYS_SOFTWARE=1
            export LP_NUM_THREADS="$LP_THREADS"
            export mesa_glthread=true
            export MESA_GL_VERSION_OVERRIDE=4.5
            export MESA_GLSL_VERSION_OVERRIDE=450
            ;;
        mesa-zink)
            export GALLIUM_DRIVER=zink
            export LIBGL_ALWAYS_SOFTWARE=0
            export MESA_GL_VERSION_OVERRIDE=4.5
            export MESA_GLSL_VERSION_OVERRIDE=450
            ;;
        dxmt)
            export SDL_RENDER_DRIVER=direct3d11
            ;;
    esac
    # Note: guard with `if`, not `&&`. A trailing `&&` that evaluates false
    # is a non-zero exit status, and under `set -e` that kills the script.
    local kv
    for kv in "${EXTRA_ENV[@]+"${EXTRA_ENV[@]}"}"; do
        if [[ -n "$kv" ]]; then
            export "${kv?}"
        fi
    done
}

step_launch() {
    require_prefix
    [[ -f "$GAME_EXE_PATH" ]] || die "$GAME_EXE not found. Run: winmac fetch $GAME_SLUG"
    [[ -x "$UPSTREAM_DIR/scripts/launch-steam.sh" ]] \
        || die "Upstream launcher missing. Run: winmac setup"

    log_step "Launching Steam for $GAME_NAME"
    kill_prefix
    _renderer_env

    log_info "Renderer : $RENDERER"
    [[ -n "${GALLIUM_DRIVER:-}"    ]] && log_info "Driver   : $GALLIUM_DRIVER"
    [[ -n "${LP_NUM_THREADS:-}"    ]] && log_info "Threads  : $LP_NUM_THREADS"

    bash "$UPSTREAM_DIR/scripts/launch-steam.sh" --detach

    cat <<EOF

  Steam is starting. Click Play on $GAME_NAME when the library appears.

  Note: the game must be launched FROM Steam. Running the .exe directly
  breaks SteamAPI init and the game crashes at address 0 before it ever
  reaches the renderer.

EOF
}

# ---------------------------------------------------------------------------
# status — what is actually doing the rendering
# ---------------------------------------------------------------------------
step_status() {
    log_step "Status"
    local pid; pid="$(pgrep -f "$GAME_EXE" | head -1 || true)"
    if [[ -z "$pid" ]]; then
        log_info "$GAME_NAME is not running. Start it, then re-run this."
        return 0
    fi

    log_ok "$GAME_NAME running (pid $pid)"
    ps -o pcpu=,rss= -p "$pid" | awk '{printf "  CPU %s%%   RAM %d MB\n",$1,$2/1024}'

    local libs
    libs="$(lsof -p "$pid" 2>/dev/null \
        | grep -oiE "winemetal|d3d11\.dll|libgallium_wgl|opengl32\.dll" | sort -u | tr '\n' ' ')"
    log_info "Loaded: ${libs:-unknown}"

    local gpu; gpu="$(ioreg -r -d 1 -w 0 -c IOAccelerator 2>/dev/null \
        | grep -o '"Device Utilization %"=[0-9]*' | head -1 | cut -d= -f2)"
    log_info "GPU utilization: ${gpu:-?}%"

    cat <<'EOF'

  Reading it:
    CPU near 100% x cores, GPU near 0   -> software rendering (llvmpipe).
                                          Lower the in-game render scale.
    CPU low, GPU busy                   -> hardware path is live.
EOF
}
