#!/usr/bin/env bash
# Set up the CachyOS/Arch half of LucasSetup: niri + Noctalia.
#
# Installs the packages, backs up whatever is already there, copies the configs
# in, generates a monitor layout for THIS machine, and points the wallpaper
# directory somewhere that exists. Safe to re-run.
#
#   ./setup.sh                  # the whole thing
#   ./setup.sh --no-install     # skip pacman/paru, just wire up configs
#   ./setup.sh --dry-run        # show what it would do
#   ./setup.sh --wallpapers DIR # use DIR for wallpapers

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIRI_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/niri"
NOCT_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/noctalia"
STAMP="$(date +%Y%m%d-%H%M%S)"

do_install=1
dry_run=0
wallpapers=""

while [ $# -gt 0 ]; do
    case "$1" in
        --no-install) do_install=0; shift ;;
        --dry-run)    dry_run=1; shift ;;
        --wallpapers) wallpapers="$2"; shift 2 ;;
        -h|--help)    sed -n '2,12p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

c_step=$'\033[36m'; c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_dim=$'\033[90m'; c_off=$'\033[0m'
step() { printf '\n%s==> %s%s\n' "$c_step" "$1" "$c_off"; }
ok()   { printf '    %sOK  %s%s\n' "$c_ok" "$1" "$c_off"; }
warn() { printf '    %sWARN %s%s\n' "$c_warn" "$1" "$c_off"; }
info() { printf '    %s%s%s\n' "$c_dim" "$1" "$c_off"; }
run()  { if [ "$dry_run" -eq 1 ]; then info "would: $*"; else "$@"; fi; }

# ------------------------------------------------------------------ install --

step "Packages"

if [ "$do_install" -eq 0 ]; then
    info "skipped (--no-install)"
elif ! command -v pacman >/dev/null 2>&1; then
    warn "not an Arch-based system - install niri and noctalia-shell yourself"
else
    need_repo=()
    for p in niri; do
        pacman -Qq "$p" >/dev/null 2>&1 && ok "$p already installed" || need_repo+=("$p")
    done
    [ ${#need_repo[@]} -gt 0 ] && run sudo pacman -S --needed --noconfirm "${need_repo[@]}"

    if pacman -Qq noctalia-shell >/dev/null 2>&1; then
        ok "noctalia-shell already installed"
    else
        helper=""
        for h in paru yay; do command -v "$h" >/dev/null 2>&1 && { helper="$h"; break; }; done
        if [ -n "$helper" ]; then
            run "$helper" -S --needed --noconfirm noctalia-shell
        else
            warn "no AUR helper (paru/yay) - install noctalia-shell manually"
        fi
    fi
fi

# ------------------------------------------------------------------- backup --

step "Backing up what's already there"

# Only back up when the installed file actually differs from what we are about
# to write - otherwise re-running piles up identical .bak files.
backed_up=0
backup_if_changed() {
    local target="$1" source="$2"
    [ -e "$target" ] || return 0
    if cmp -s "$target" "$source"; then
        info "$(basename "$target") unchanged"
        return 0
    fi
    # setup.sh rewrites settings.toml after copying it, so the installed file
    # never matches the repo copy. Don't re-save a backup we already have.
    local existing
    for existing in "$target".bak-*; do
        [ -e "$existing" ] || continue
        if cmp -s "$target" "$existing"; then
            info "$(basename "$target") already backed up"
            return 0
        fi
    done
    run cp -a "$target" "$target.bak-$STAMP"
    ok "$(basename "$target") -> $(basename "$target").bak-$STAMP"
    backed_up=1
}

backup_if_changed "$NIRI_DIR/config.kdl"    "$REPO_DIR/niri/config.kdl"
backup_if_changed "$NIRI_DIR/noctalia.kdl"  "$REPO_DIR/niri/noctalia.kdl"
backup_if_changed "$NOCT_DIR/settings.toml" "$REPO_DIR/noctalia/settings.toml"
backup_if_changed "$NOCT_DIR/state.toml"    "$REPO_DIR/noctalia/state.toml"

[ "$backed_up" -eq 0 ] && info "nothing needed backing up"

# ------------------------------------------------------------------- copy ----

step "Installing configs"

run mkdir -p "$NIRI_DIR" "$NOCT_DIR"
run cp "$REPO_DIR/niri/config.kdl"   "$NIRI_DIR/config.kdl"
run cp "$REPO_DIR/niri/noctalia.kdl" "$NIRI_DIR/noctalia.kdl"
ok "niri config"

for f in settings.toml state.toml; do
    run cp "$REPO_DIR/noctalia/$f" "$NOCT_DIR/$f"
done
ok "noctalia settings"

# ---------------------------------------------------------------- monitors ---
# config.kdl does `include "outputs.kdl"`, and a MISSING include is a hard
# config error - so this file must always exist, even if we can't detect
# anything useful. An empty one just means "let niri auto-detect".

step "Monitor layout"

if [ "$dry_run" -eq 1 ]; then
    info "would generate $NIRI_DIR/outputs.kdl"
elif niri msg --json outputs >/dev/null 2>&1; then
    "$REPO_DIR/gen-outputs.sh" -o "$NIRI_DIR/outputs.kdl" >/dev/null
    ok "generated from the monitors niri currently sees"
    sed 's/^/        /' "$NIRI_DIR/outputs.kdl" | grep -v '^\s*$' || true
else
    cat > "$NIRI_DIR/outputs.kdl" <<'PLACEHOLDER'
// No niri session was running when setup.sh ran, so there is no monitor
// layout here yet - niri will auto-detect and stack your monitors.
//
// Once you are logged into niri, run gen-outputs.sh to capture the real
// layout, or write output blocks here by hand.
PLACEHOLDER
    ok "placeholder written (niri auto-detects until you run gen-outputs.sh)"
    info "not in a niri session - run ./gen-outputs.sh after logging in"
fi

# --------------------------------------------------------------- wallpapers --

step "Wallpapers"

if [ -z "$wallpapers" ]; then
    committed=$(python3 - "$REPO_DIR/noctalia/settings.toml" <<'PY'
import re, sys
m = re.search(r'^\s*directory\s*=\s*"([^"]*)"', open(sys.argv[1]).read(), re.M)
print(m.group(1) if m else '')
PY
)
    if [ -n "$committed" ] && [ -d "$committed" ]; then
        wallpapers="$committed"
    else
        for cand in "$(xdg-user-dir PICTURES 2>/dev/null || true)" "$HOME/Pictures"; do
            [ -n "$cand" ] && [ -d "$cand" ] && { wallpapers="$cand"; break; }
        done
    fi
fi

if [ -z "$wallpapers" ] || [ ! -d "$wallpapers" ]; then
    warn "no wallpaper directory found - set one in Noctalia settings"
elif [ "$dry_run" -eq 1 ]; then
    info "would point wallpapers at $wallpapers"
else
    python3 - "$NOCT_DIR/settings.toml" "$wallpapers" <<'PY'
import re, sys

path, wall = sys.argv[1], sys.argv[2]
text = open(path).read()
original = text

# Point the wallpaper directory at something that exists on this machine.
text = re.sub(r'(^\s*directory\s*=\s*)"[^"]*"',
              lambda m: m.group(1) + '"%s"' % wall, text, count=1, flags=re.M)

# Favourites are pointers to specific files on the other machine - drop the
# whole entry rather than leaving one with no path behind.
text = re.sub(r'^[ \t]*\[\[wallpaper\.favorite\]\]\n(?:[ \t]*[a-z_]+ = .*\n)*',
              '', text, flags=re.M)

# Same for the remaining specific wallpaper files - Noctalia will pick from
# the directory instead of showing a blank background.
text = re.sub(r'^\s*path\s*=\s*"[^"]*"\n', '', text, flags=re.M)

if text != original:
    open(path, 'w').write(text)

# Re-read so a bad rewrite fails here rather than inside Noctalia.
try:
    import tomllib
    with open(path, 'rb') as fh:
        tomllib.load(fh)
except ModuleNotFoundError:
    pass
except Exception as e:
    sys.exit('settings.toml is no longer valid TOML: %s' % e)
PY
    ok "wallpaper directory -> $wallpapers"
    info "stale wallpaper file paths cleared; pick one in Noctalia"
fi

# --------------------------------------------------------------- app check ---

step "Applications the keybinds expect"

missing=()
while IFS='|' read -r bin desc; do
    if command -v "$bin" >/dev/null 2>&1; then
        ok "$(printf '%-14s' "$bin")$desc"
    else
        warn "$(printf '%-14s' "$bin")$desc  - NOT INSTALLED"
        missing+=("$bin")
    fi
done <<'APPS'
noctalia|the shell itself (bar, dock, lockscreen)
ghostty|Mod+T terminal
brave|Mod+B browser
cosmic-files|Mod+F file manager
btop|Ctrl+Shift+Esc system monitor
APPS

if [ ${#missing[@]} -gt 0 ]; then
    info "install them, or edit the spawn lines in $NIRI_DIR/config.kdl"
fi

# ---------------------------------------------------------------- validate ---

step "Validating"

if command -v niri >/dev/null 2>&1 && [ "$dry_run" -eq 0 ]; then
    if niri validate -c "$NIRI_DIR/config.kdl" >/dev/null 2>&1; then
        ok "niri says the config is valid"
    else
        warn "niri validate failed:"
        niri validate -c "$NIRI_DIR/config.kdl" 2>&1 | sed 's/^/        /' || true
        exit 1
    fi
else
    info "skipped"
fi

step "Done"
if niri msg --json outputs >/dev/null 2>&1; then
    info "already in niri - reload with Mod+Shift+R, or restart Noctalia"
else
    info "log out and pick niri, or run niri-session from a TTY"
fi
