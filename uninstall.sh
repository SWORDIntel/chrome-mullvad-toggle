#!/usr/bin/env bash
set -euo pipefail

purge=false
if [ "${1:-}" = --purge ]; then
    purge=true
elif [ $# -gt 0 ]; then
    echo "Usage: ./uninstall.sh [--purge]" >&2
    exit 2
fi

config_home=${XDG_CONFIG_HOME:-$HOME/.config}
data_home=${XDG_DATA_HOME:-$HOME/.local/share}
bin_home=${XDG_BIN_HOME:-$HOME/.local/bin}
install_dir=$data_home/chrome-mullvad-toggle

pkill -f "$install_dir/chrome-mullvad-tray.py" 2>/dev/null || true
rm -f "$config_home/autostart/chrome-mullvad-tray.desktop"
rm -f "$data_home/applications/chrome-mullvad-toggle.desktop"
rm -f "$bin_home/chrome-mullvad-toggle"

for file in check-ip chrome-mullvad-tray.py toggle-chrome-mullvad; do
    rm -f "$install_dir/$file"
done
for icon in green red gray amber; do
    rm -f "$install_dir/icons/chrome-vpn-$icon.svg"
done
rmdir "$install_dir/icons" 2>/dev/null || true
rmdir "$install_dir" 2>/dev/null || true

sudo systemctl disable --now chrome-split-nat.timer 2>/dev/null || true
sudo rm -f /etc/systemd/system/chrome-split-nat.service /etc/systemd/system/chrome-split-nat.timer
sudo rm -f /usr/local/libexec/chrome-mullvad-toggle/setup-split-nat
sudo rmdir /usr/local/libexec/chrome-mullvad-toggle 2>/dev/null || true
sudo nft delete table inet chrome-split 2>/dev/null || true
sudo systemctl daemon-reload

if $purge; then
    rm -f "$config_home/chrome-mullvad-toggle/config"
    rmdir "$config_home/chrome-mullvad-toggle" 2>/dev/null || true
fi

command -v update-desktop-database >/dev/null && update-desktop-database "$data_home/applications" 2>/dev/null || true
echo "Uninstalled Chrome Mullvad Toggle"
