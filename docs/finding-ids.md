# Finding the IDs

A game config needs four things: the app ID, the depot ID, the manifest ID, and
the executable name.

## App ID

The number in the store URL:

```
https://store.steampowered.com/app/686060/Mewgenics/
                                   ^^^^^^
```

Confirm you have the right one. An app ID typo silently downloads a completely
different product, which is easy to miss when the download is 4 GB of opaque
depot data.

## Depot ID and manifest ID

### From an existing appmanifest

If you have ever started the download, even one that failed, Steam wrote an
`appmanifest_<appid>.acf` and it contains both IDs:

```bash
cat "$HOME/.wine-steam/drive_c/Program Files (x86)/Steam/steamapps/appmanifest_686060.acf"
```

Look for `InstalledDepots` or `StagedDepots`:

```
"StagedDepots"
{
    "686061"                                  <- depot ID
    {
        "manifest"    "8229879464648565847"   <- manifest ID
        "size"        "5056804332"
    }
}
```

This is the most reliable source, because it is the exact build Steam intended
to give your account.

### From SteamDB

Open `https://steamdb.info/app/<appid>/depots/`. Pick the depot holding the
Windows content, then open its Manifests tab and take the current public
manifest ID.

Watch out for depots that are language packs, soundtracks, or DLC. The content
depot is normally the large one, and its ID is often the app ID plus one.

## Folder name and executable

If the game is already unpacked:

```bash
ls "$HOME/.wine-steam/drive_c/Program Files (x86)/Steam/steamapps/common/"
```

If not, `GAME_DIR` is the `installdir` value in the appmanifest, and the
executable name usually matches the game name. `winmac fetch` will tell you if
it cannot find what your config claims, and you can list the folder afterwards.

Both values are case-sensitive and space-sensitive.

## Checking the download landed correctly

`download_depot` prints a byte total when it finishes. Compare it against the
`size` in the manifest:

```bash
find "$HOME/.wine-steam/drive_c/Program Files (x86)/Steam/steamapps/common/Mewgenics" \
    -type f -exec stat -f "%z" {} \; | awk '{s+=$1} END {print s}'
```

An exact match means the download is complete and intact. A shortfall usually
means a file is still arriving; `download_depot` writes them one at a time and
the last one can lag well behind the others.
