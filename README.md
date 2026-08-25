# LucasSetup

My desktop configs for both machines: a **CachyOS** box running niri + Noctalia, and a
**Windows** box running an AutoHotkey window manager + PowerToys.

```
cachyos/    niri compositor, Noctalia shell, nirimod, generated app themes, setup.sh
windows/    AutoHotkey v2 window manager, VD.ah2 library, PowerToys backup, Setup.ps1
```

---

## CachyOS setup

See [`cachyos/README.md`](cachyos/README.md) for the full file-by-file map of what came from where.

### Quick start: `setup.sh`

```fish
cd cachyos
./setup.sh
```

It installs everything the config needs, backs up anything already in place, copies the
configs in, **generates a monitor layout for the machine you are on**, points the
wallpaper directory at somewhere that exists, and finishes by running `niri validate`
on the result.

Packages installed — the apps the keybinds spawn are included, so no key is left dead:

| Needed | Package | For |
| --- | --- | --- |
| `niri` | `niri` (repo) | the compositor |
| `noctalia` | `noctalia-shell` (repo) | the shell — bar, dock, lockscreen |
| `ghostty` | `ghostty` (repo) | `Mod+T` terminal |
| `brave` | `brave-bin` (AUR) | `Mod+B` browser |
| `cosmic-files` | `cosmic-files` (repo) | `Mod+F` file manager |
| `btop` | `btop` (repo) | `Ctrl+Shift+Esc` system monitor |

Repo packages go through `pacman`; anything not in the repos falls back to `paru`/`yay`.
Both run with `--noconfirm`, so AUR builds are installed **without a PKGBUILD review** —
use `--no-install` and install by hand if you would rather look first.

Detection is by *provide*, not package name, so a variant you already run counts and is
left alone — on a machine with `niri-tearing-git` and `noctalia-git` it reports
`satisfied by niri-tearing-git` and installs nothing.

| Flag | Effect |
| --- | --- |
| `--no-install` | Skip pacman/paru, just wire up configs (still reports what's missing) |
| `--dry-run` | Print what it would do, change nothing |
| `--wallpapers DIR` | Use `DIR` instead of auto-detecting |

Safe to re-run: files that already match are left alone, and it will not re-save a backup
identical to one it already has.

### Monitors: `gen-outputs.sh`

The monitor layout is the least portable part of a niri config — output names, exact
refresh rates and pixel positions are all specific to one desk. So it lives in its own
`outputs.kdl`, which `config.kdl` pulls in with `include`, and which this script writes:

```fish
cd cachyos
./gen-outputs.sh            # writes ~/.config/niri/outputs.kdl
./gen-outputs.sh --stdout   # just print it
```

Run it inside a niri session — it reads `niri msg --json outputs`, so it captures the
monitors as they are actually connected and arranged right now. Re-run it whenever you
plug in, unplug, or rearrange a monitor.

> **`outputs.kdl` must exist.** A missing `include` target is a hard config error — niri
> refuses to load the config at all, not just the output block. `setup.sh` always writes
> the file, falling back to a comments-only placeholder (which means "auto-detect") when
> it can't reach a running niri. If you delete it by hand, niri will not start.

### Doing it by hand

The rest of this section is what `setup.sh` automates.

### 1. Install the pieces

```fish
# niri is in the CachyOS/Arch repos
sudo pacman -S niri

# Noctalia shell (AUR)
paru -S noctalia-shell
```

`nirimod` is optional — it is a config manager for niri that keeps rolling backups.
Skip it if you just want the raw config.

### 2. Drop the configs in place

```fish
mkdir -p ~/.config/niri ~/.local/state/noctalia ~/.config/nirimod

cp cachyos/niri/config.kdl        ~/.config/niri/
cp cachyos/niri/noctalia.kdl      ~/.config/niri/
cp cachyos/niri/outputs.kdl       ~/.config/niri/   # required - see above
cp cachyos/noctalia/settings.toml ~/.local/state/noctalia/
cp cachyos/noctalia/state.toml    ~/.local/state/noctalia/
cp cachyos/nirimod/settings.json  ~/.config/nirimod/
cp -r cachyos/nirimod/baseline    ~/.config/nirimod/
```

`config.kdl` includes `noctalia.kdl` for its colors, so both files need to be present.
`config.kdl.orig` is the stock niri config, kept only for diffing.

### 3. Fix the machine-specific bits

- **Monitors** — run `./gen-outputs.sh` inside niri to rewrite `outputs.kdl`. The
  Noctalia lockscreen widgets in `settings.toml` also name `DP-2`/`HDMI-A-1`, but that
  block is `enabled = false`, so stale names there are inert.
- **Wallpapers** — `[wallpaper]` points at `/mnt/hdd/MEGA/Pictures/Catgirls`. Point
  `directory` at your own folder and clear the `path` entries, or Noctalia will show a blank
  background until you pick a new wallpaper.
- **Apps** — the keybinds spawn `ghostty` (Mod+T), `brave` (Mod+B), `cosmic-files` (Mod+F)
  and `btop` (Ctrl+Shift+Esc) by name; `setup.sh` installs all four. If you prefer
  something else, edit those `spawn` lines — a missing binary just makes the key do nothing.

### 4. Log in and regenerate themes

Log out and pick **niri** at the display manager, or run `niri-session` from a TTY.

Everything under `cachyos/themes/` is *generated* by Noctalia's template system from the
active palette (currently the community palette **Cream Autumn**, dark mode). You do not
need to copy those files — open Noctalia's settings, confirm the enabled templates under
`[theme.templates]`, and it will rewrite them for gtk3/4, btop, kitty, alacritty, ghostty,
cava, qt5ct/qt6ct, and the KDE color scheme. They are committed only as a record of what
the palette produced.

---

## Windows setup

Two independent layers that work together: AutoHotkey does the window/desktop management,
PowerToys provides FancyZones and remaps the awkward hotkeys into comfortable ones.

### Quick start: `Setup.ps1`

`windows/Setup.ps1` does the whole thing. Open PowerShell in the `windows\` folder:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Setup.ps1
```

It will:

1. **Install** Brave, AutoHotkey v2, Windows Terminal and PowerToys via `winget`
   (skipping anything already present).
2. **Detect** where they actually landed on this machine — Brave via the
   `App Paths` registry key first, then the usual per-user and Program Files
   locations — plus your real `%LOCALAPPDATA%` and `%WINDIR%`.
3. **Rewrite** the machine-specific paths baked into `powertoys-settings.ptb` and
   write a patched copy into `Documents\PowerToys\Backup`. The JSON is re-validated
   after patching, so a bad rewrite fails loudly instead of producing a backup
   PowerToys silently rejects.
4. **Create** the NewPlus templates folder if it does not exist yet.
5. **Wire up** AutoHotkey: a Startup shortcut pointing at `WindowManager.ahk` with its
   working directory set to the repo folder (the script `#Include`s `VD.ah2` from
   there), then starts it.

The one thing it does not automate is the PowerToys restore itself — that is a GUI
action. The script prints the exact filename to pick in
Settings → General → Backup & restore → Restore.

| Flag | Effect |
| --- | --- |
| `-SkipInstall` | Skip `winget` entirely; just detect, patch and wire up |
| `-ApplyDirect` | Write settings straight into PowerToys' live folder instead of leaving a `.ptb` to restore by hand. Stops PowerToys, backs up the existing settings first, then restarts it |
| `-NoStartup` | Don't create the Startup shortcut |

#### Re-running it

Every step is safe to repeat — nothing errors out because it was already done:

| Step | On a second run |
| --- | --- |
| winget installs | Checked with `winget list` first and skipped. A failed check is harmless — winget just reports "already installed" and the script continues |
| Path detection | Read-only |
| NewPlus folder | Created only if missing |
| Patched `.ptb` | Fixed filename, overwritten each run — no clutter, and the name to pick in the restore dialog never changes |
| Startup shortcut | Overwritten in place |
| `WindowManager.ahk` | Relaunched; `#SingleInstance Force` replaces the running copy |
| `-ApplyDirect` | Copies the current settings to `...\Microsoft\PowerToys.before-lucassetup-<timestamp>` before overwriting, so each run leaves another rollback point. Delete old ones by hand |

The one step that is *not* tracked is the PowerToys restore itself — the script has no way
to tell whether you clicked Restore, so it will re-patch and ask again. Harmless.

If you install Brave after the fact, `.\Setup.ps1 -SkipInstall` picks up the new path and
rewrites the backup.

**Keep the repo folder where it is** — the Startup shortcut points at it by path.

The rest of this section is what the script automates, in case you'd rather do it by hand.

### 1. AutoHotkey window manager

Requires **[AutoHotkey v2](https://www.autohotkey.com/)** — v1 will not run this script.

1. Install AutoHotkey v2.
2. Copy `windows/WindowManager.ahk` and `windows/VD.ah2` into the **same folder** — the
   script does `#Include %A_ScriptDir%\VD.ah2`, so they must sit side by side.
3. Double-click `WindowManager.ahk` to run it.
4. To start it at login: press `Win+R`, run `shell:startup`, and put a shortcut to
   `WindowManager.ahk` in the folder that opens.

`VD.ah2` is the [VD.ahk](https://github.com/FuPeiJiang/VD.ahk) virtual-desktop library. It
talks to undocumented Windows COM interfaces and is **version-sensitive** — if virtual
desktop hotkeys stop working after a Windows update, grab a newer `VD.ah2` from upstream.

#### Hotkeys

| Keys | Action |
| --- | --- |
| `Ctrl+Alt+Win+A` / `D` | Focus previous / next window, left-to-right on the current monitor |
| `Ctrl+Alt+Win+W` / `S` | Focus the monitor above / below |
| `Ctrl+Alt+Win+M` | Toggle maximize |
| `Ctrl+Win+Shift+,` / `.` | Move window to the monitor above / below |
| `Ctrl+Win+Shift+Z` / `X` | Go to previous / next virtual desktop |
| `Ctrl+Alt+Win+Z` / `X` | Move window to previous / next desktop and follow it |
| `Ctrl+Alt+Win+1`–`8` | Move window to desktop 1–8 and follow it |
| `Win+Alt+Shift+1`–`8` | Go to desktop 1–8 |
| `Win+Shift+E` | Pin window to all desktops + always on top |

The script keeps a 100ms focus tracker running so that when the desktop itself has focus
(after closing a window, say), the next hotkey restores focus to the last real window
instead of doing nothing.

### 2. PowerToys

`windows/powertoys-settings.ptb` is a PowerToys settings backup taken from **v0.100.2**.

1. Install [PowerToys](https://github.com/microsoft/PowerToys) (`winget install Microsoft.PowerToys`).
2. Copy `powertoys-settings.ptb` into your backup folder — by default
   `%USERPROFILE%\Documents\PowerToys\Backup`.
3. Open PowerToys Settings → **General** → **Backup & restore** → **Restore**.
4. Restart PowerToys.

Enabled modules in this backup: AlwaysOnTop, Awake, CmdPal, ColorPicker, FancyZones,
File Explorer add-ons, File Locksmith, FindMyMouse, Image Resizer, Keyboard Manager,
Measure Tool, MouseHighlighter, Peek, PowerRename, Shortcut Guide. Everything else is off.
It also has "run at startup" and "run elevated" turned on — elevated is what lets the
hotkeys work over admin windows.

#### The two layers fit together

Keyboard Manager is doing real work here, not just convenience. It remaps the simple
chords onto the three-modifier hotkeys the AHK script listens for:

- `Win+1`…`Win+5` → `Win+Alt+Shift+1`…`5`, i.e. **switch to desktop 1–5**
- `Win+A` → `Ctrl+Alt+Win+A`, i.e. **cycle window focus**
- `Win+B`, `Win+D`, … → launch apps directly

So after restoring, `Win+1` switches virtual desktops instead of opening the first taskbar
app. If you only restore PowerToys without running the AHK script, those remaps will fire
into nothing.

#### Machine-specific paths

Four paths in the backup were captured from the PC it came from. `Setup.ps1` rewrites all
of them; fix them by hand in PowerToys Settings if you restored the raw `.ptb` yourself:

| Where | Path | Bound to |
| --- | --- | --- |
| Keyboard Manager | `...\AppData\Local\BraveSoftware\...\brave.exe` | `Win+B` |
| Keyboard Manager | `...\AppData\Local\Microsoft\WindowsApps\wt.exe` | `Win+T` |
| Keyboard Manager | `C:\Windows\explorer.exe` | `Win+F` |
| NewPlus | `...\AppData\Local\Microsoft\PowerToys\NewPlus\Templates` | template folder |

All four contain the old username `lucasdonald`, except `explorer.exe`.

---

## Not included

Regenerated automatically or personal to a machine — see [`.gitignore`](.gitignore):
Noctalia clipboard and notification history, usage counters, downloaded community palettes
and templates, plugins, and nirimod's rolling backups.
