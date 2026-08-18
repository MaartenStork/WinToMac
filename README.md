# winmac

Run Windows-only Steam games on Apple Silicon Macs, driven by a single config file.

You describe a game in `games/<name>.conf`, then run `winmac play <name>`. The
pipeline downloads the Windows build, installs it into a Wine prefix, applies
the renderer workarounds that game needs, and launches it.

```bash
./winmac doctor            # check the environment
./winmac setup             # Wine 11 + Steam + steamwebhelper wrapper
./winmac play mewgenics    # fetch, configure, launch
./winmac status mewgenics  # is the GPU or the CPU doing the work?
```

## Why this exists

Getting a Windows-only game running on an Apple Silicon Mac in 2026 means
walking through four separate problems, each of which fails in a way that does
not obviously point at the real cause:

1. **Steam will not download it.** It refuses a Windows-only title on macOS.
2. **Steam will not run.** The popular free option, Whisky, is frozen at Wine
   7.7 from 2022, and the modern Steam client cannot render its own UI on it.
   You get an endless `steamwebhelper is not responding` dialog.
3. **Steam will not log in.** With a broken UI there is nothing to click, and
   Steam waits forever unless auto-login is already enabled.
4. **The game will not draw.** Wine's macOS OpenGL driver frequently cannot
   create a context, and games that do not check the return value die with a
   page fault at address `0`.

Each stage here corresponds to one of those, and `docs/troubleshooting.md`
lists the exact error text for every failure mode we hit.

## Requirements

- Apple Silicon Mac (built and verified on an M4 Pro)
- macOS 26 or later
- Homebrew
- Xcode Command Line Tools
- About 15 GB free, plus the size of the game
- You must **own** the game on Steam

## Install

```bash
git clone https://github.com/<you>/winmac.git
cd winmac
./winmac doctor
./winmac setup
```

`setup` clones [notpop/steam-on-m1-wine][upstream] and hands off to it. That
project does the heavy lifting: Wine 11, a dedicated prefix, Steam, and a
`steamwebhelper` wrapper that forces CEF into `--disable-gpu --single-process`.
Without that wrapper, Steam cannot draw its own interface under Wine.

Use its `--minimal` installer. The full build compiles LLVM 15 and DXMT for
Direct3D 11 support; it takes about an hour and is useless for OpenGL games.

## Adding a game

```bash
cp games/EXAMPLE.conf games/mygame.conf
$EDITOR games/mygame.conf
./winmac play mygame
```

The config needs the Steam app ID, the depot ID, the manifest ID, the folder
name, and the executable name. See [docs/finding-ids.md](docs/finding-ids.md).

## How it works

**Downloading.** Steam's `download_depot <appid> <depotid> <manifestid>`
console command names the depot explicitly, so the platform check never runs
and your normal macOS Steam client will happily fetch a Windows build. The
files land inside the Steam `.app` bundle rather than your library folder,
which is why this is scripted. `winmac fetch` then moves them into the prefix
and writes an `appmanifest` so Steam treats the game as installed.

**Rendering.** This is where most of the work is. Wine's `winemac.drv` OpenGL
is unreliable on current macOS, so the default path installs [Mesa for
Windows][mesa] next to the game executable and overrides `opengl32` to native.

The important detail, and the one that costs people an afternoon: the override
must be **per-application**. Setting `WINEDLLOVERRIDES=opengl32=n` prefix-wide
makes Steam itself try to load Mesa's DLL, which it cannot find, and Steam dies
with `Could not load module 'bin/vgui2_s.dll'`. `winmac` writes the override to
`HKCU\Software\Wine\AppDefaults\<exe>\DllOverrides` so only the game sees it.

**Verifying.** `winmac status` is the antidote to guesswork. It reports CPU
percentage, GPU utilization, and which graphics libraries the running process
actually loaded. A game pinned at 900% CPU with 0% GPU is software rendering,
whatever your config claims.

## Renderer options

| `RENDERER` | Path | When |
|---|---|---|
| `mesa-llvmpipe` | OpenGL on the CPU | Default. Reliable, slow. Lower the in-game render scale. |
| `mesa-zink` | OpenGL on Vulkan on Metal | GPU accelerated when it works. Often fails on pixel format selection. |
| `dxmt` | Direct3D 11 on Metal | Only for engines that genuinely call D3D11. |
| `native` | Wine's own OpenGL | Try first. If it page-faults at address 0, switch to Mesa. |

Do not assume a game uses D3D11 because its binary contains D3D11 symbols.
Anything built on SDL ships every backend it was compiled with. Mewgenics has a
complete SDL3 D3D11 renderer inside it and never calls a single function of it.

## Status and scope

This has been verified end to end on **one game**, Mewgenics, on one machine.
The stages are general and the config format is game-agnostic, but every game
is its own adventure, and the renderer table above is a starting point rather
than a guarantee.

Contributions of working `games/*.conf` files are the most useful thing you
could add.

### Known issue: the Wine cask is deprecated

Homebrew has deprecated the `wine-stable` cask because it fails the macOS
Gatekeeper check, and it is scheduled for removal on **2026-09-01**. Existing
installations keep working. Fresh ones may not, which means this pipeline may
become non-reproducible from scratch. If you have a working
`/Applications/Wine Stable.app`, do not delete it.

## Upstream bugs found while building this

Reported so others do not lose the same hours:

- `steam-on-m1-wine` pins meson with `pip install --user`, which PEP 668 blocks
  on current Python. Its wrapper step also fails on a first run, because Steam
  only downloads its CEF files when it first launches.
- meson below 1.11 is required by DXMT, but 1.10 crashes on cross builds with
  `KeyError: build.cpp_importstd`. The usable range is 1.9.x.
- `steam-on-m1-wine`'s Wine toolchain step assumes the tarball extracts into a
  `wine-*` directory; it extracts flat.
- DXMT's `src/util/com/com_guid.cpp` uses `std::setfill` and `std::setw`
  without including `<iomanip>`, which fails on GCC 16.

## Credits

- [notpop/steam-on-m1-wine][upstream] — the Wine 11 and Steam stack, and the
  `steamwebhelper` wrapper that makes modern Steam usable under Wine
- [pal1000/mesa-dist-win][mesa] — Mesa builds for Windows
- [3Shain/dxmt](https://github.com/3Shain/dxmt) — Direct3D 11 on Metal

## License

MIT. See [LICENSE](LICENSE).

[upstream]: https://github.com/notpop/steam-on-m1-wine
[mesa]: https://github.com/pal1000/mesa-dist-win
