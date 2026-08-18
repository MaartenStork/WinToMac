# Upstream bugs

Problems found in dependencies while building this, written down so nobody
loses the same hours. Fixes are in [troubleshooting.md](troubleshooting.md).

## steam-on-m1-wine

**The meson pin uses `pip install --user`, which PEP 668 blocks.**
On current Python this fails with `error: externally-managed-environment` and
the build stops. A virtualenv works.

**The required meson version is narrower than the check assumes.**
The script pins to 1.10.1 when it finds 1.11 or newer, because DXMT's
`meson.build` doesn't work on 1.11+. But 1.10 crashes on cross builds:

```
KeyError: 'Tried to access nonexistant project parent option build.cpp_importstd.'
ERROR: Unhandled python exception
```

`cpp_importstd` was introduced in 1.10, so the usable range is 1.9.x.

**The Wine toolchain extraction assumes a wrapper directory.**
It looks for an extracted `wine-*` folder to rename, but the tarball extracts
flat, putting `bin/`, `lib/`, `include/` and `share/` straight into
`toolchains/`. The build then stops with `winebuild not found`.

**The wrapper step fails on a first run.**
Step 06 needs `Steam/bin/cef`, but `SteamSetup.exe` only installs `steam.exe`;
Steam downloads its CEF files when it first launches. So the installer always
fails the first time with `Steam CEF directory not found`. Launching Steam
once, then re-running the installer, fixes it. Worth documenting rather than
fixing, since it's inherent to how Steam bootstraps.

## DXMT

**`com_guid.cpp` is missing an include.**
It uses `std::setfill` and `std::setw` without including `<iomanip>`, relying
on a transitive include that GCC 16 no longer provides:

```
../src/util/com/com_guid.cpp:64:26: error: 'setfill' is not a member of 'std'
```

Adding `#include <iomanip>` fixes it.

**Building from source needs full Xcode.**
The build compiles Metal shaders via `xcrun metal`, which ships with Xcode, not
Command Line Tools:

```
xcrun: error: unable to find utility "metal", not a developer tool or in PATH
```

Worth checking whether you need the source build at all. The prebuilt DXMT that
steam-on-m1-wine installs is usually enough, and for an OpenGL game DXMT is
irrelevant regardless.

## Homebrew

**The `wine-stable` cask is deprecated and scheduled for removal on
2026-09-01**, because it fails the macOS Gatekeeper check. Existing
installations keep working. Fresh ones may not, which means this pipeline could
become impossible to reproduce from scratch.

If you have a working `/Applications/Wine Stable.app`, don't delete it.
`winmac doctor` warns about this.
