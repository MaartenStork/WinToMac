# How it works

## The stack

```
   Your Windows game                  an unmodified Windows .exe
        |
   Mesa OpenGL                        real OpenGL, sitting next to the .exe,
        |                             because Wine's macOS GL driver is broken
   Steam for Windows                  the game must be launched from here
        |
   Wine 11                            translates Windows API calls into macOS
        |
   Rosetta 2                          runs Wine's x86_64 binary on Apple Silicon
        |
   macOS on Apple Silicon
```

Wine is the core of this. It translates Windows API calls into macOS ones
rather than emulating a PC, and Rosetta 2 handles x86 to ARM instruction
translation underneath it. Neither is emulation in the console-emulator sense,
which is why the CPU cost is modest and why graphics is the part that breaks.

The Mesa layer is the only place we step outside Wine, and even then Wine is
still loading and running it. We just tell Wine to use Mesa's `opengl32`
instead of its own, for one executable.

## The four stages

Each stage matches one of the four things that break.

## 1. Downloading

Steam refuses to install a Windows-only game on macOS. The console command
`download_depot <appid> <depotid> <manifestid>` names the depot explicitly, so
the platform check never runs and your normal macOS Steam client fetches the
Windows build without complaint.

The files land inside the Steam `.app` bundle rather than your library folder,
which is easy to miss:

```
~/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/steamapps/content/app_<id>/depot_<id>/
```

`winmac fetch` knows where to look, moves the files into the Wine prefix, and
writes an `appmanifest` with `StateFlags 4` so Steam treats the game as
installed rather than trying to download it again.

## 2. Running Steam

Whisky and Apple's Game Porting Toolkit are frozen at Wine 7.7 from 2022. The
modern Steam client cannot render its own interface on that, which is what the
endless `steamwebhelper is not responding` dialog means.

Wine 11 fixes it, combined with a wrapper that forces Steam's embedded Chromium
into `--disable-gpu --single-process`. Both come from
[steam-on-m1-wine](https://github.com/notpop/steam-on-m1-wine), which `winmac
setup` clones and runs. We drive that project rather than duplicating it.

## 3. Logging in

Steam can hold valid cached credentials and still sit there forever, because
`AllowAutoLogin` is `0` and it's waiting for a click on a UI that isn't
drawing. Setting auto-login lets it connect without the interface.

## 4. Drawing

This is where most of the work is.

Wine's macOS OpenGL driver often cannot create a context. Games that don't
check the return value then call a NULL function pointer and die with a page
fault at address `0`.

The fix is to install [Mesa for Windows](https://github.com/pal1000/mesa-dist-win)
next to the game executable and override `opengl32` to native, which gives the
game a real OpenGL implementation that doesn't depend on Wine's Mac driver.

**The override must be per-application.** Setting
`WINEDLLOVERRIDES=opengl32=n` prefix-wide makes Steam itself try to load Mesa's
DLL from its own directory, fail, and die with `Could not load module
'bin/vgui2_s.dll'`. winmac writes it to
`HKCU\Software\Wine\AppDefaults\<exe>\DllOverrides` so only the game sees it.

## Verifying instead of guessing

`winmac status` reports CPU usage, GPU utilization, and which graphics
libraries the running process actually loaded. This matters more than it
sounds: a game can have `d3d11.dll` and `winemetal` loaded while doing all its
drawing on the CPU, because those libraries were probed and discarded.

CPU near several hundred percent with GPU near zero means software rendering,
whatever the config says.

## Things worth knowing

**Launch from Steam, not the .exe.** Running the executable directly breaks
SteamAPI initialisation and crashes at address `0` before any renderer code
runs. Testing renderer settings from a terminal tests nothing.

**D3D11 symbols don't mean D3D11.** Any game built on SDL ships every backend
SDL was compiled with. Mewgenics contains a complete SDL3 Direct3D 11 renderer
and never calls it, because its engine draws in OpenGL directly.
