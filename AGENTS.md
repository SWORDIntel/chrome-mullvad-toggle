# Agent Notes

## Architecture

- `chrome-mullvad-tray.py` — GTK3 + Ayatana AppIndicator system-tray indicator. Polls Chrome process cgroups every 2 seconds and publishes red/green/amber status.
- `toggle-chrome-mullvad` — Shell script that toggles running Chrome PIDs between Mullvad and direct routing using `mullvad split-tunnel add/delete`.
- `check-ip` — Opens Mullvad's connection check page in the configured browser.
- `setup-split-nat` — Root script that maintains an nftables masquerade rule for excluded traffic. Auto-detects the Mullvad interface and default egress interface.
- `install.sh` / `uninstall.sh` — User-level installer with dependency detection, browser autodiscovery, optional NAT workaround, and autostart.
- `systemd/` — systemd service and timer for the NAT workaround.
- `icons/` — SVG status icons (green, red, amber, gray).

## Key design decisions

- Status detection reads `/proc/<pid>/cgroup` rather than relying solely on `mullvad split-tunnel list`, because Mullvad moves processes into the `net_cls:/mullvad-exclusions` cgroup even when the CLI list is empty.
- The NAT workaround is optional and auto-detected. Some hosts need it (Mullvad leaves the tunnel source address on excluded traffic); others do not.
- All paths are resolved at install time and written to `$XDG_CONFIG_HOME/chrome-mullvad-toggle/config`. No hardcoded home paths in the runtime scripts.
- The installer respects XDG Base Directory specification (`XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_BIN_HOME`).

## Testing

```bash
python3 -m unittest -v test_tray_status.py
bash -n toggle-chrome-mullvad check-ip setup-split-nat install.sh uninstall.sh
desktop-file-validate chrome-mullvad-tray.desktop toggle-chrome-mullvad.desktop
```

## Rules

Apply Inquisitor code rules and qlearn project intelligence. See canonical rule paths in the parent INFRA `AGENTS.md`.
