#!/usr/bin/env bash
#
# install.sh — install lang2lang with all dependencies.
#
# Usage:
#   ./install.sh              # full install (system packages + uv + sync)
#   ./install.sh --no-system  # skip system packages (needs sudo)
#   ./install.sh --no-uv      # skip uv installation
#
set -euo pipefail

# ---------- colors ----------
if [[ -t 1 ]]; then
    RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; BLUE=$'\e[34m'; NC=$'\e[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
fi

info()  { printf '%s==>%s %s\n' "$BLUE" "$NC" "$*"; }
ok()    { printf '%s✔%s %s\n' "$GREEN" "$NC" "$*"; }
warn()  { printf '%s⚠%s %s\n' "$YELLOW" "$NC" "$*"; }
err()   { printf '%s✘%s %s\n' "$RED" "$NC" "$*" >&2; }
die()   { err "$*"; exit 1; }

# ---------- argument parsing ----------
DO_SYSTEM=1
DO_UV=1
for arg in "$@"; do
    case "$arg" in
        --no-system) DO_SYSTEM=0 ;;
        --no-uv)     DO_UV=0 ;;
        -h|--help)
            sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) die "Unknown argument: $arg" ;;
    esac
done

# ---------- sanity checks ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

[[ -f "pyproject.toml" ]] || die "pyproject.toml not found in $SCRIPT_DIR — run this script from the project directory."
[[ -f "lang2lang.py" ]]  || die "lang2lang.py not found in $SCRIPT_DIR."

if [[ "$(uname -s)" != "Linux" ]]; then
    die "This script targets Linux (detected: $(uname -s))."
fi

# Detect distribution
DISTRO=""
if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO_ID="${ID:-}"
    DISTRO_LIKE="${ID_LIKE:-}"
else
    DISTRO_ID=""; DISTRO_LIKE=""
fi

detect_pkg_family() {
    case " $DISTRO_ID $DISTRO_LIKE " in
        *" debian "*|*" ubuntu "*|*" linuxmint "*|*" pop "*|*" elementary "*) echo "debian" ;;
        *" fedora "*|*" rhel "*|*" centos "*|*" nobara "*)                    echo "fedora" ;;
        *" arch "*|*" archlinux "*|*" manjaro "*|*" endeavouros "*)             echo "arch" ;;
        *" opensuse "*|*" suse "*)                                             echo "suse" ;;
        *)                                                                     echo "unknown" ;;
    esac
}
PKG_FAMILY="$(detect_pkg_family)"

# ---------- check required system dependencies ----------
REQUIRED_BINS=(gsettings gdbus xdotool)
OPTIONAL_BINS=(paplay)

missing_bins=()
for b in "${REQUIRED_BINS[@]}"; do
    command -v "$b" >/dev/null 2>&1 || missing_bins+=("$b")
done

# tkinter check
TKINTER_OK=0
if python3 -c "import tkinter" 2>/dev/null; then
    TKINTER_OK=1
fi

# GNOME Shell + Shyriiwook check
check_shyriiwook() {
    if ! command -v gdbus >/dev/null 2>&1; then
        return 1
    fi
    local out
    out="$(gdbus introspect --session \
        --dest org.gnome.Shell \
        --object-path /me/madhead/Shyriiwook 2>&1 || true)"
    if [[ "$out" == *"me.madhead.Shyriiwook"* ]]; then
        return 0
    fi
    return 1
}

# ---------- install system packages ----------
install_system_packages() {
    info "Installing system packages (family: ${PKG_FAMILY})..."

    local need_sudo=0
    [[ "$(id -u)" -ne 0 ]] && need_sudo=1
    local SUDO=""
    [[ $need_sudo -eq 1 ]] && SUDO="sudo"

    case "$PKG_FAMILY" in
        debian)
            $SUDO apt-get update
            $SUDO apt-get install -y \
                xdotool pulseaudio-utils python3-tk libglib2.0-bin \
                curl ca-certificates
            ;;
        fedora)
            $SUDO dnf install -y \
                xdotool pulseaudio-utils python3-tkinter glib2 \
                curl ca-certificates
            ;;
        arch)
            $SUDO pacman -Sy --needed --noconfirm \
                xdotool libpulse tk glib2 \
                curl ca-certificates
            ;;
        suse)
            $SUDO zypper install -y \
                xdotool pulseaudio-utils python3-tk libglib-2_0-0 glib2-tools \
                curl ca-certificates
            ;;
        *)
            warn "Unknown distribution. Install these manually:"
            warn "  xdotool, pulseaudio-utils (paplay), python3-tk, glib2 (gsettings/gdbus)"
            return 1
            ;;
    esac
    ok "System packages installed."
}

if [[ $DO_SYSTEM -eq 1 ]]; then
    if [[ ${#missing_bins[@]} -gt 0 || $TKINTER_OK -eq 0 ]]; then
        if [[ ${#missing_bins[@]} -gt 0 ]]; then
            warn "Missing utilities: ${missing_bins[*]}"
        fi
        [[ $TKINTER_OK -eq 0 ]] && warn "Python tkinter module not found."
        install_system_packages || warn "Automatic install failed — please install manually."
    else
        ok "System dependencies are already present."
    fi
else
    info "Skipping system package installation (--no-system)."
fi

# ---------- install uv ----------
install_uv() {
    if command -v uv >/dev/null 2>&1; then
        ok "uv already installed: $(uv --version)"
        return 0
    fi

    info "Installing uv..."

    if command -v pipx >/dev/null 2>&1; then
        info "Found pipx — using pipx install uv."
        pipx install uv
    else
        info "Installing uv via the official script."
        curl -LsSf https://astral.sh/uv/install.sh | sh
    fi

    # Update PATH for the current session
    export PATH="$HOME/.local/bin:$PATH"

    if ! command -v uv >/dev/null 2>&1; then
        # try to find it in standard locations
        for p in "$HOME/.local/bin/uv" "$HOME/.cargo/bin/uv" "/usr/local/bin/uv"; do
            if [[ -x "$p" ]]; then
                export PATH="$(dirname "$p"):$PATH"
                break
            fi
        done
    fi

    command -v uv >/dev/null 2>&1 || die "uv was installed but is not on PATH. Add ~/.local/bin to PATH and re-run the script."

    ok "uv installed: $(uv --version)"
}

if [[ $DO_UV -eq 1 ]]; then
    install_uv
else
    command -v uv >/dev/null 2>&1 || die "uv not found and installation was skipped (--no-uv)."
    info "Skipping uv installation (--no-uv)."
fi

# ---------- check Python 3.12 ----------
info "Checking Python 3.12..."
if ! uv python list 2>/dev/null | grep -q '^cpython-3\.12'; then
    info "Python 3.12 not found in uv — installing it."
    uv python install 3.12
fi
ok "Python 3.12 is available."

# ---------- install project dependencies ----------
info "Syncing project environment (uv sync)..."
uv sync
ok "Project environment is synced."

# ---------- check error.wav ----------
if [[ ! -f "$SCRIPT_DIR/error.wav" ]]; then
    warn "error.wav not found in $SCRIPT_DIR — the error sound will be silently skipped."
fi

# ---------- check GNOME/Shyriiwook ----------
info "Checking GNOME Shyriiwook extension..."
if check_shyriiwook; then
    ok "Shyriiwook is reachable via D-Bus."
else
    warn "Could not confirm that Shyriiwook is available."
    warn "Make sure the extension is installed:"
    warn "  https://github.com/madhead/shyriiwook"
    warn "and that more than one input source is configured in GNOME."
fi

# ---------- summary ----------
echo
ok "Installation complete."
echo
printf 'Manual test (select some text with the mouse, then run):\n'
printf '  %s\n' "uv run python lang2lang.py --convert en"
printf '  %s\n' "uv run python lang2lang.py --convert ru"
printf '  %s\n' "uv run python lang2lang.py --convert ua"
echo
printf 'Assign hotkeys in GNOME:\n'
printf '  Settings → Keyboard → Keyboard Shortcuts → Custom Shortcuts\n'
printf 'Example command:\n'
printf '  %s\n' "$HOME/.local/bin/uv run $SCRIPT_DIR/.venv/bin/python $SCRIPT_DIR/lang2lang.py --convert ru"
echo
printf 'Logs: %s\n' "/tmp/lang2lang.log"
