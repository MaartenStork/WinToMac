# winmac

Play **Steam** games that only ship a Windows build on your Apple Silicon Mac,
set up from a single config file.

```bash
./winmac play mewgenics
```

## What this is

**Steam only.** Everything here runs through Steam: the game is downloaded
using Steam's own depot system, installed into a Steam library inside a Wine
prefix, and launched from the Steam client. It is for games you already own on
Steam that have no macOS version. It is not for GOG, Epic, itch.io, or
standalone installers.

Getting such a game running on a Mac means solving four separate problems:
Steam won't download the game, Steam won't run, Steam won't log in, and then
the game won't draw anything. Each one fails with an error that doesn't point
at the real cause.

winmac wraps all four into one pipeline. You describe a game in a config file,
run one command, and it downloads the Windows build, installs it into a Wine
prefix, applies the graphics workarounds that game needs, and launches it
through Steam.

Verified end to end on Mewgenics. The pipeline is game-agnostic, but every game
is its own adventure.

## Requirements

- Apple Silicon Mac, macOS 26 or later
- Homebrew and Xcode Command Line Tools
- ~15 GB free, plus the size of the game
- **A Steam account that owns the game.** winmac downloads it with your own
  Steam client, using your own license. It does not bypass ownership.

## Setup

```bash
git clone https://github.com/MaartenStork/WinToMac.git
cd WinToMac
./winmac doctor     # check your machine
./winmac setup      # install Wine 11 + Steam
```

`setup` clones [steam-on-m1-wine][upstream] and runs its installer. That project
provides Wine 11, the prefix, Steam, and a `steamwebhelper` wrapper that stops
Steam's UI from crashing. Use its `--minimal` flag; the full build takes an hour
and only helps Direct3D 11 games.

It will ask for your password once, and the wrapper step fails the first time
by design. [docs/troubleshooting.md](docs/troubleshooting.md) covers it.

## Adding a game

```bash
cp games/EXAMPLE.conf games/mygame.conf
$EDITOR games/mygame.conf
./winmac play mygame
```

You need the Steam app ID, depot ID, manifest ID, folder name, and executable
name. [docs/finding-ids.md](docs/finding-ids.md) shows where to get them.

## Commands

| | |
|---|---|
| `winmac doctor` | check the environment |
| `winmac setup` | install Wine and Steam |
| `winmac list` | show configured games |
| `winmac fetch <game>` | download the Windows build into the prefix |
| `winmac install <game>` | apply graphics workarounds |
| `winmac launch <game>` | start Steam, ready to play |
| `winmac status <game>` | is the GPU or the CPU doing the work? |
| `winmac play <game>` | all of the above |

## Docs

- [How it works](docs/how-it-works.md): what each stage actually does
- [Choosing a renderer](docs/renderers.md): read this if the game won't draw
- [Finding the IDs](docs/finding-ids.md): filling in a config
- [Troubleshooting](docs/troubleshooting.md): every error we hit, with fixes
- [Upstream bugs](docs/upstream-bugs.md): problems found in dependencies

## Contributing

Working `games/*.conf` files are the most useful thing you can add.

## Credits

Built on [notpop/steam-on-m1-wine][upstream], [pal1000/mesa-dist-win][mesa],
and [3Shain/dxmt](https://github.com/3Shain/dxmt).

MIT licensed.

[upstream]: https://github.com/notpop/steam-on-m1-wine
[mesa]: https://github.com/pal1000/mesa-dist-win
