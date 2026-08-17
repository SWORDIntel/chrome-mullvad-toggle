<div align="center">

# 🟢🔴 Chrome Mullvad Toggle

### Keep your VPN on everything *except* your browser — with one click.

A Linux desktop utility that lets you flip Chrome or Chromium between your Mullvad VPN tunnel and your raw ISP connection **without restarting the browser**, complete with a live system-tray status light.

![Green](icons/chrome-vpn-green.svg) &nbsp;**Protected** &nbsp;&nbsp;&nbsp; ![Red](icons/chrome-vpn-red.svg) &nbsp;**Exposed** &nbsp;&nbsp;&nbsp; ![Amber](icons/chrome-vpn-amber.svg) &nbsp;**Mixed**

[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux-desktops-orange.svg)](#)

</div>

---

## Why?

Sometimes you want **everything** behind Mullvad — your terminal, your package manager, your SSH sessions — but your browser needs the raw connection: for streaming, for banking, for that one site that blocks VPN exits, or just for speed.

Restarting Chrome every time is annoying. Mullvad has split-tunnel exclusion built in, but there's no GUI for it and the CLI is tedious when you're juggling 20+ Chrome processes.

This fixes that. **One click. No restart. Live status light.**

## ✨ Features

- **One-click toggle** — flip your entire browser between Mullvad and direct, no restart
- **Live tray indicator** — green/red/amber light that updates every 2 seconds
- **Cgroup-accurate detection** — reads `/proc` directly, doesn't trust the stale CLI list
- **Auto-installs everything** — detects apt/dnf/pacman/zypper/apk and bootstraps deps
- **Smart NAT workaround** — auto-probes and only installs the firewall fix if you actually need it
- **Chrome or Chromium** — auto-detected, or override with `--browser`
- **XDG-compliant** — respects your directory structure, no hardcoded paths
- **Autostart** — tray launches at login, survives reboots

## 🚀 Quick start

```bash
git clone https://github.com/SWORDIntel/chrome-mullvad-toggle.git
cd chrome-mullvad-toggle
./install.sh
```

That's it. The installer will:

1. 📦 Detect your distro and install any missing dependencies
2. 🌐 Find your browser (Chrome or Chromium)
3. 📋 Install scripts, icons, and desktop entries
4. 🔧 Probe whether you need the NAT workaround (and set it up if so)
5. 🟢 Launch the tray indicator

## 🎛️ Install options

```
./install.sh [options]

  --browser PATH              Point to a specific Chrome/Chromium binary
  --nat-workaround MODE       auto | on | off  (default: auto)
  --no-autostart              Don't launch the tray at login
  --no-bootstrap-deps         Skip automatic dependency installation
  --help                      Show help
```

## 🖱️ Usage

### Tray menu

Click the icon in your system tray:

| Action | What it does |
|--------|-------------|
| **Toggle Chrome routing** | Flips all running browser processes between Mullvad and direct, then opens a connection check page |
| **Open Mullvad connection check** | Opens `https://mullvad.net/en/check` in a new tab |
| **Quit indicator** | Exits the tray app |

### Command line

```bash
chrome-mullvad-toggle
```

If Chrome isn't running yet, this launches it **outside** Mullvad and opens the check page. If it is running, it toggles the current routing.

### What the colors mean

| | Color | State |
|---|---|---|
| 🟢 | Green | Browser is behind Mullvad — your traffic is protected |
| 🔴 | Red | Browser is on your raw ISP connection (or Chrome is closed) |
| 🟡 | Amber | Some Chrome processes are excluded and some aren't — something's mixed up |

## 🧠 How it works

### The toggle

Uses Mullvad's native split-tunnel exclusion (`mullvad split-tunnel add/delete <PID>`) to move Chrome processes in and out of the VPN tunnel **without killing them**. When you click toggle:

- **→ Direct:** every Chrome PID gets added to Mullvad's exclusion list
- **→ Mullvad:** every Chrome PID gets removed from the exclusion list

### The status light

Here's the non-obvious part: `mullvad split-tunnel list` is **unreliable**. Mullvad moves processes into its `net_cls:/mullvad-exclusions` cgroup but doesn't always reflect that in the CLI output. So instead of trusting the list, the indicator reads each Chrome process's `/proc/<pid>/cgroup` directly and checks whether it's in the exclusion cgroup. That's why the light is actually accurate.

### The NAT workaround

On some network setups (bridged interfaces, certain router configs), Mullvad's firewall leaves excluded traffic with the tunnel's source IP address. Your ISP gateway sees traffic from a foreign IP and drops the return packets — so "excluded" Chrome has no internet at all.

The installer detects this by running `mullvad-exclude curl` against Mullvad's API. If it fails, it installs a systemd timer that maintains an nftables masquerade rule, source-NATting excluded traffic to your egress interface so the gateway accepts it.

You don't have to think about any of this. It just works.

## 📦 Manual dependency installation

Prefer to install things yourself? Pass `--no-bootstrap-deps`:

<details>
<summary><b>Debian / Ubuntu</b></summary>

```bash
sudo apt install python3-gi gir1.2-ayatanaappindicator3-0.1 libnotify-bin iproute2
```
</details>

<details>
<summary><b>Fedora</b></summary>

```bash
sudo dnf install python3-gobject libayatana-appindicator-gtk3 libnotify iproute
```
</details>

<details>
<summary><b>Arch Linux</b></summary>

```bash
sudo pacman -S python-gobject libayatana-appindicator libnotify iproute2
```
</details>

<details>
<summary><b>openSUSE</b></summary>

```bash
sudo zypper install python3-gobject libayatana-appindicator-gtk3 libnotify iproute2
```
</details>

<details>
<summary><b>Alpine</b></summary>

```bash
sudo apk add py3-gobject3 libayatana-appindicator libnotify iproute2
```
</details>

> **Note:** Mullvad VPN itself must be installed from [mullvad.net](https://mullvad.net/en/download/linux) — it's not in most distro repos.

## 🗑️ Uninstall

```bash
./uninstall.sh          # remove everything
./uninstall.sh --purge  # also wipe the config file
```

## 📁 Project layout

```
chrome-mullvad-toggle/
├── chrome-mullvad-tray.py       # GTK3 + Ayatana tray indicator
├── toggle-chrome-mullvad        # Toggle script (the actual switch)
├── check-ip                     # Opens Mullvad's connection check
├── setup-split-nat              # NAT workaround (runs as root)
├── install.sh                   # The installer
├── uninstall.sh                 # The uninstaller
├── systemd/                     # Timer + service for NAT workaround
├── icons/                       # SVG status icons (green/red/amber/gray)
├── test_tray_status.py          # Unit tests for status logic
└── .github/workflows/test.yml   # CI: syntax, tests, shellcheck, desktop validation
```

## 📄 License

AGPL-3.0-or-later. See [LICENSE](LICENSE).

---

<div align="center">

[Report a bug](https://github.com/SWORDIntel/chrome-mullvad-toggle/issues) · [Request a feature](https://github.com/SWORDIntel/chrome-mullvad-toggle/issues)

</div>
