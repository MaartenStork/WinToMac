# Troubleshooting

Every entry here is a failure we actually hit, with the exact text it printed.

## `steamwebhelper is not responding` / `The Steam UI will not be usable`

**Cause.** You are on Whisky, or any Wine older than about 9.x. Whisky and
Apple's Game Porting Toolkit are frozen at Wine 7.7 from 2022, and the modern
Steam client's CEF build will not run on it. None of the dialog's own options
(restart, disable GPU, disable sandbox) fix it, and neither does any Steam
launch flag.

**Fix.** Use Wine 11 with the `steamwebhelper` wrapper. `winmac setup` does it.

## Steam starts but never logs in, with no visible window

**Cause.** Cached credentials exist but `AllowAutoLogin` is `0`, so Steam waits
for a click on a UI that is not rendering.

**Fix.** In the prefix's `config/loginusers.vdf` set `"AllowAutoLogin" "1"`, and
set `AutoLoginUser` in the registry:

```bash
export WINEPREFIX="$HOME/.wine-steam"
wine reg add 'HKCU\Software\Valve\Steam' /v AutoLoginUser /d YOUR_ACCOUNT /f
wine reg add 'HKCU\Software\Valve\Steam' /v RememberPassword /t REG_DWORD /d 1 /f
```

## `Fatal Error: Could not load module 'bin/vgui2_s.dll'`

**Cause.** A prefix-wide `opengl32` override. `WINEDLLOVERRIDES=opengl32=n`
applies to every process in the prefix, including Steam, which then tries to
load Mesa's `opengl32.dll` from its own directory and fails.

**Fix.** Scope the override to the game executable only:

```bash
wine reg add 'HKCU\Software\Wine\AppDefaults\YourGame.exe\DllOverrides' \
    /v opengl32 /d native /f
```

This is what `winmac install` does.

## `Could not create gl context` / page fault at address `0`

```
Unhandled page fault on read access to 0000000000000000 at address 0000000000000000
rip:0000000000000000
```

**Cause.** Wine's `winemac.drv` OpenGL failed to create a context. The game did
not check the return value, called a NULL function pointer, and died. The
modules list in the crash dump shows `opengl32` loaded.

**Fix.** `RENDERER="mesa-llvmpipe"`, which supplies a real OpenGL
implementation next to the executable.

## `Could not create window: No matching GL pixel format available`

**Cause.** Progress, actually: Mesa is loading and being asked for pixel
formats. With `GALLIUM_DRIVER=zink` it creates real Vulkan devices on the GPU
but cannot offer a pixel format SDL will accept, because of Mesa's WGL layer
running on Wine's Vulkan.

**Fix.** `RENDERER="mesa-llvmpipe"`. Software rendering enumerates the full
standard set of formats.

## `SteamAPI_Init() Failed. Steam must be running to play this game.`

**Cause.** You launched the `.exe` directly instead of through Steam.

**Fix.** Always launch from Steam's library. Note that a direct launch does not
merely show this dialog: it can crash at address `0` during SteamAPI startup,
long before any renderer code runs. If you are testing renderer settings from a
terminal, you are testing nothing. Launch from Steam.

## Game runs, but is slow

Run `winmac status <game>`. If you see CPU near several hundred percent and GPU
near zero, you are on `llvmpipe` and rendering on the CPU.

In order of effect:

1. **Lower the in-game render scale.** 70% is roughly half the pixels of 100%,
   and llvmpipe scales almost linearly with pixel count. This dwarfs everything
   else.
2. Leave `LP_THREADS` at the default, which is your performance core count.
3. Do not chase `dxmt` unless `winmac status` shows the game actually loading
   `d3d11.dll` and `winemetal` for rendering rather than merely probing them.

## Audio crackling or stuttering

Usually not an audio bug. Software rendering saturates every core, audio
buffers underrun, and you hear it. Lower the render scale first. If it persists
on a game that is not CPU-bound, try `WINDOWS_VERSION="winxp"` in the config,
which several communities report helps with older audio paths.

## `error: externally-managed-environment` during upstream's build

**Cause.** PEP 668. `pip install --user` is blocked on current Python.

**Fix.** Use a virtualenv and point the build at it:

```bash
python3 -m venv ~/.local/share/dxmt-meson
~/.local/share/dxmt-meson/bin/pip install 'meson==1.9.0'
MESON="$HOME/.local/share/dxmt-meson/bin/meson" bash install.sh
```

Use 1.9.x specifically. DXMT needs meson below 1.11, but 1.10 crashes on cross
builds with `KeyError: 'Tried to access nonexistant project parent option
build.cpp_importstd.'`

## `Wine toolchain extracted but winebuild not found`

**Cause.** The build script expects the tarball to extract into a `wine-*`
directory. It extracts flat.

**Fix.**

```bash
cd ~/dev/dxmt/toolchains
mkdir -p wine && mv bin include lib share wine/
```

## `'setfill' is not a member of 'std'`

**Cause.** DXMT's `src/util/com/com_guid.cpp` relies on a transitive include
that GCC 16 no longer provides.

**Fix.** Add `#include <iomanip>` at the top of that file.

## `xcrun: error: unable to find utility "metal"`

**Cause.** Building DXMT from source needs Apple's Metal compiler, which ships
with full Xcode, not Command Line Tools.

**Fix.** Install Xcode, or skip it. The prebuilt DXMT that upstream's step 04
installs is usually all you need, and for an OpenGL game DXMT is irrelevant
anyway. Check before spending 15 GB: a real DXMT `d3d11.dll` is several MB.

```bash
ls -lh "/Applications/Wine Stable.app/Contents/Resources/wine/lib/wine/x86_64-windows/d3d11.dll"
```
