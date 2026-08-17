#!/usr/bin/env bash
set -euo pipefail

base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
browser_override=""
nat_mode=auto
autostart=true
bootstrap_deps=true

usage() {
    cat <<'EOF'
Usage: ./install.sh [options]
  --browser PATH              Use a specific Chrome or Chromium executable
  --nat-workaround MODE       auto, on, or off (default: auto)
  --no-autostart              Do not start the tray indicator at login
  --no-bootstrap-deps         Do not attempt to install missing dependencies
  --help                      Show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --browser)
            [ $# -ge 2 ] || { echo "--browser requires a path" >&2; exit 2; }
            browser_override=$2
            shift 2
            ;;
        --nat-workaround)
            [ $# -ge 2 ] || { echo "--nat-workaround requires auto, on, or off" >&2; exit 2; }
            nat_mode=$2
            shift 2
            ;;
        --no-autostart)
            autostart=false
            shift
            ;;
        --no-bootstrap-deps)
            bootstrap_deps=false
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$nat_mode" in
    auto|on|off) ;;
    *) echo "Invalid NAT workaround mode: $nat_mode" >&2; exit 2 ;;
esac

# --- Dependency detection and bootstrapping ---

detect_package_manager() {
    if command -v apt-get >/dev/null; then
        echo apt
    elif command -v dnf >/dev/null; then
        echo dnf
    elif command -v pacman >/dev/null; then
        echo pacman
    elif command -v zypper >/dev/null; then
        echo zypper
    elif command -v apk >/dev/null; then
        echo apk
    else
        echo unknown
    fi
}

install_packages() {
    local pm
    pm=$(detect_package_manager)
    case "$pm" in
        apt)
            sudo apt-get update -qq
            sudo apt-get install -y "$@"
            ;;
        dnf)
            sudo dnf install -y "$@"
            ;;
        pacman)
            sudo pacman -Sy --noconfirm --needed "$@"
            ;;
        zypper)
            sudo zypper install -y "$@"
            ;;
        apk)
            sudo apk add "$@"
            ;;
        *)
            echo "Unable to install packages: no supported package manager found" >&2
            echo "Please install manually: $*" >&2
            return 1
            ;;
    esac
}

missing_commands=()
for command_name in python3 mullvad mullvad-exclude ip awk readlink notify-send; do
    command -v "$command_name" >/dev/null || missing_commands+=("$command_name")
done

if [ ${#missing_commands[@]} -gt 0 ]; then
    if $bootstrap_deps; then
        pm=$(detect_package_manager)
        echo "Missing commands: ${missing_commands[*]}"
        case "$pm" in
            apt)
                echo "Bootstrapping dependencies via apt..."
                install_packages python3 python3-gi \
                    gir1.2-ayatanaappindicator3-0.1 \
                    libnotify-bin iproute2 mullvad-vpn
                ;;
            dnf)
                echo "Bootstrapping dependencies via dnf..."
                install_packages python3 python3-gobject \
                    libayatana-appindicator-gtk3 libnotify \
                    iproute mullvad-vpn
                ;;
            pacman)
                echo "Bootstrapping dependencies via pacman..."
                install_packages python python-gobject \
                    libayatana-appindicator libnotify \
                    iproute2 mullvad-vpn
                ;;
            zypper)
                echo "Bootstrapping dependencies via zypper..."
                install_packages python3 python3-gobject \
                    libayatana-appindicator-gtk3 libnotify \
                    iproute2 mullvad-vpn
                ;;
            apk)
                echo "Bootstrapping dependencies via apk..."
                install_packages python3 py3-gobject3 \
                    libayatana-appindicator libnotify \
                    iproute2 mullvad-vpn
                ;;
            *)
                echo "No supported package manager found. Please install: ${missing_commands[*]}" >&2
                exit 1
                ;;
        esac
        # Re-check after installation
        for command_name in "${missing_commands[@]}"; do
            command -v "$command_name" >/dev/null || {
                echo "Command $command_name still missing after bootstrap" >&2
                exit 1
            }
        done
    else
        echo "Missing required commands: ${missing_commands[*]}" >&2
        exit 1
    fi
fi

# Check Python GTK/AppIndicator bindings and bootstrap if missing
if ! python3 -c 'import gi; gi.require_version("Gtk", "3.0"); gi.require_version("AyatanaAppIndicator3", "0.1")' 2>/dev/null; then
    if $bootstrap_deps; then
        pm=$(detect_package_manager)
        echo "Missing Python GTK3 or Ayatana AppIndicator bindings."
        case "$pm" in
            apt)
                echo "Bootstrapping via apt..."
                install_packages python3-gi gir1.2-ayatanaappindicator3-0.1
                ;;
            dnf)
                echo "Bootstrapping via dnf..."
                install_packages python3-gobject libayatana-appindicator-gtk3
                ;;
            pacman)
                echo "Bootstrapping via pacman..."
                install_packages python-gobject libayatana-appindicator
                ;;
            zypper)
                echo "Bootstrapping via zypper..."
                install_packages python3-gobject libayatana-appindicator-gtk3
                ;;
            apk)
                echo "Bootstrapping via apk..."
                install_packages py3-gobject3 libayatana-appindicator
                ;;
            *)
                echo "No supported package manager. Please install PyGObject and Ayatana AppIndicator manually." >&2
                exit 1
                ;;
        esac
        python3 -c 'import gi; gi.require_version("Gtk", "3.0"); gi.require_version("AyatanaAppIndicator3", "0.1")' 2>/dev/null || {
            echo "Python GTK/AppIndicator bindings still missing after bootstrap" >&2
            exit 1
        }
    else
        echo "Missing Python GTK3 or Ayatana AppIndicator bindings." >&2
        echo "Debian/Ubuntu: sudo apt install python3-gi gir1.2-ayatanaappindicator3-0.1" >&2
        echo "Fedora: sudo dnf install python3-gobject libayatana-appindicator-gtk3" >&2
        echo "Arch: sudo pacman -S python-gobject libayatana-appindicator" >&2
        exit 1
    fi
fi

browser_command=$browser_override
if [ -n "$browser_command" ]; then
    browser_command=$(readlink -f "$browser_command")
else
    for candidate in google-chrome-stable google-chrome chromium chromium-browser; do
        candidate_path=$(command -v "$candidate" 2>/dev/null || true)
        if [ -n "$candidate_path" ]; then
            browser_command=$(readlink -f "$candidate_path")
            break
        fi
    done
fi

[ -x "$browser_command" ] || { echo "No supported Chrome or Chromium executable was found" >&2; exit 1; }
if [ -x "$(dirname "$browser_command")/chrome" ]; then
    browser_process=$(readlink -f "$(dirname "$browser_command")/chrome")
else
    browser_process=$browser_command
fi

config_home=${XDG_CONFIG_HOME:-$HOME/.config}
data_home=${XDG_DATA_HOME:-$HOME/.local/share}
bin_home=${XDG_BIN_HOME:-$HOME/.local/bin}
install_dir=$data_home/chrome-mullvad-toggle
config_dir=$config_home/chrome-mullvad-toggle
applications_dir=$data_home/applications
autostart_dir=$config_home/autostart

install -d "$install_dir/icons" "$config_dir" "$applications_dir" "$autostart_dir" "$bin_home"
install -m 755 "$base/src/check-ip" "$base/src/chrome-mullvad-tray.py" "$base/src/toggle-chrome-mullvad" "$install_dir/"
install -m 644 "$base/icons/"*.svg "$install_dir/icons/"
printf 'BROWSER_COMMAND=%s\nBROWSER_PROCESS=%s\n' "$browser_command" "$browser_process" > "$config_dir/config"
chmod 600 "$config_dir/config"

cat > "$bin_home/chrome-mullvad-toggle" <<EOF
#!/usr/bin/env bash
exec "$install_dir/toggle-chrome-mullvad" "\$@"
EOF
chmod 755 "$bin_home/chrome-mullvad-toggle"

cat > "$applications_dir/chrome-mullvad-toggle.desktop" <<EOF
[Desktop Entry]
Version=1.0
Name=Toggle Chrome Mullvad
GenericName=Browser VPN Toggle
Comment=Toggle the running browser between Mullvad and the normal connection
Exec=$install_dir/toggle-chrome-mullvad
StartupNotify=false
Terminal=false
Icon=$install_dir/icons/chrome-vpn-green.svg
Type=Application
Categories=Network;WebBrowser;
EOF

if $autostart; then
    cat > "$autostart_dir/chrome-mullvad-tray.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Chrome Mullvad Status
Comment=Show browser Mullvad routing status in the system tray
Exec=$install_dir/chrome-mullvad-tray.py
Icon=$install_dir/icons/chrome-vpn-red.svg
Terminal=false
StartupNotify=false
X-GNOME-Autostart-enabled=true
EOF
else
    rm -f "$autostart_dir/chrome-mullvad-tray.desktop"
fi

command -v update-desktop-database >/dev/null && update-desktop-database "$applications_dir" 2>/dev/null || true

if [ "$nat_mode" = auto ]; then
    if command -v nft >/dev/null && nft list table inet chrome-split >/dev/null 2>&1; then
        nat_mode=on
    elif command -v curl >/dev/null && curl -4 -fsS --max-time 10 https://am.i.mullvad.net/json >/dev/null 2>&1; then
        if mullvad-exclude curl -4 -fsS --max-time 10 https://am.i.mullvad.net/json >/dev/null 2>&1; then
            nat_mode=off
        else
            nat_mode=on
        fi
    else
        nat_mode=off
    fi
fi

if [ "$nat_mode" = on ]; then
    command -v nft >/dev/null || { echo "nft is required for the NAT workaround" >&2; exit 1; }
    sudo install -D -m 755 "$base/src/setup-split-nat" /usr/local/libexec/chrome-mullvad-toggle/setup-split-nat
    sudo install -m 644 "$base/systemd/chrome-split-nat.service" /etc/systemd/system/chrome-split-nat.service
    sudo install -m 644 "$base/systemd/chrome-split-nat.timer" /etc/systemd/system/chrome-split-nat.timer
    sudo systemctl daemon-reload
    sudo systemctl enable --now chrome-split-nat.timer
    sudo systemctl start chrome-split-nat.service
else
    sudo systemctl disable --now chrome-split-nat.timer 2>/dev/null || true
fi

pkill -f "$install_dir/chrome-mullvad-tray.py" 2>/dev/null || true
if $autostart; then
    nohup "$install_dir/chrome-mullvad-tray.py" >"$HOME/.cache/chrome-mullvad-tray.log" 2>&1 &
fi

printf 'Installed Chrome Mullvad Toggle\nBrowser: %s\nProcess: %s\nNAT workaround: %s\n' "$browser_command" "$browser_process" "$nat_mode"
