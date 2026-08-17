#!/usr/bin/env python3
from __future__ import annotations

import logging
import os
import shutil
import subprocess
from pathlib import Path

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("AyatanaAppIndicator3", "0.1")
from gi.repository import AyatanaAppIndicator3, GLib, Gtk

BASE_DIR = Path(__file__).resolve().parent
ICON_DIR = BASE_DIR / "icons"
TOGGLE_COMMAND = BASE_DIR / "toggle-chrome-mullvad"
CHECK_COMMAND = BASE_DIR / "check-ip"
CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "chrome-mullvad-toggle"
CONFIG_PATH = CONFIG_DIR / "config"
BROWSER_CANDIDATES = ("google-chrome-stable", "google-chrome", "chromium", "chromium-browser")
REFRESH_SECONDS = 2
COMMAND_TIMEOUT_SECONDS = 5

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")


def _browser_process_path() -> str | None:
    try:
        values = {}
        for line in CONFIG_PATH.read_text(encoding="utf-8").splitlines():
            key, separator, value = line.partition("=")
            if separator:
                values[key.strip()] = value.strip()
        configured = values.get("BROWSER_PROCESS")
        if configured and Path(configured).is_absolute():
            return os.path.realpath(configured)
    except (FileNotFoundError, PermissionError, OSError):
        pass

    for candidate in BROWSER_CANDIDATES:
        command = shutil.which(candidate)
        if not command:
            continue
        resolved = Path(command).resolve()
        chrome_binary = resolved.parent / "chrome"
        return str(chrome_binary.resolve() if chrome_binary.is_file() else resolved)
    return None


def _chrome_pids() -> set[int]:
    browser_process = _browser_process_path()
    if not browser_process:
        return set()
    pids: set[int] = set()
    for proc in Path("/proc").glob("[0-9]*"):
        try:
            if os.path.realpath(proc / "exe") == browser_process:
                pids.add(int(proc.name))
        except (FileNotFoundError, PermissionError, ValueError, OSError):
            continue
    return pids


def _explicitly_excluded_pids() -> set[int]:
    try:
        result = subprocess.run(
            ["mullvad", "split-tunnel", "list"],
            capture_output=True,
            check=True,
            text=True,
            timeout=COMMAND_TIMEOUT_SECONDS,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        logging.error("Unable to query Mullvad exclusions: %s", exc)
        return set()

    pids: set[int] = set()
    for line in result.stdout.splitlines():
        value = line.strip()
        if value.isdigit():
            pids.add(int(value))
    return pids


def _pid_is_excluded(pid: int, explicit: set[int]) -> bool:
    if pid in explicit:
        return True
    try:
        cgroups = Path(f"/proc/{pid}/cgroup").read_text(encoding="utf-8")
    except (FileNotFoundError, PermissionError, OSError):
        return False
    return any(
        line.endswith(":net_cls:/mullvad-exclusions") or line.endswith("::/mullvad-exclusions")
        for line in cgroups.splitlines()
    )


def _status() -> tuple[str, str, str]:
    chrome = _chrome_pids()
    if not chrome:
        return "red", "Chrome stopped", "Not protected until launched through Mullvad"

    explicit = _explicitly_excluded_pids()
    excluded = {pid for pid in chrome if _pid_is_excluded(pid, explicit)}
    if len(excluded) == len(chrome):
        return "red", "Chrome outside Mullvad", f"Direct connection · {len(chrome)}/{len(chrome)} processes excluded"
    if not excluded:
        return "green", "Chrome using Mullvad", f"Protected by Mullvad · {len(chrome)} processes"
    return "amber", "Chrome routing mixed", f"Warning · {len(excluded)}/{len(chrome)} processes excluded"


class ChromeMullvadTray:
    def __init__(self) -> None:
        self._children: list[subprocess.Popen[bytes]] = []
        self._indicator = AyatanaAppIndicator3.Indicator.new(
            "chrome-mullvad-toggle",
            "chrome-vpn-gray",
            AyatanaAppIndicator3.IndicatorCategory.SYSTEM_SERVICES,
        )
        self._indicator.set_icon_theme_path(str(ICON_DIR))
        self._indicator.set_status(AyatanaAppIndicator3.IndicatorStatus.ACTIVE)

        menu = Gtk.Menu()
        self._status_item = Gtk.MenuItem(label="Checking Chrome routing…")
        self._status_item.set_sensitive(False)
        menu.append(self._status_item)

        self._detail_item = Gtk.MenuItem(label="")
        self._detail_item.set_sensitive(False)
        menu.append(self._detail_item)

        menu.append(Gtk.SeparatorMenuItem())

        toggle_item = Gtk.MenuItem(label="Toggle Chrome routing")
        toggle_item.connect("activate", self._on_toggle)
        menu.append(toggle_item)

        check_item = Gtk.MenuItem(label="Open Mullvad connection check")
        check_item.connect("activate", self._on_check)
        menu.append(check_item)

        menu.append(Gtk.SeparatorMenuItem())

        quit_item = Gtk.MenuItem(label="Quit indicator")
        quit_item.connect("activate", self._on_quit)
        menu.append(quit_item)

        menu.show_all()
        self._indicator.set_menu(menu)
        self._refresh()
        GLib.timeout_add_seconds(REFRESH_SECONDS, self._refresh)

    def _spawn(self, command: Path) -> None:
        try:
            child = subprocess.Popen([str(command)])
        except OSError as exc:
            logging.error("Unable to run %s: %s", command, exc)
            return
        self._children = [process for process in self._children if process.poll() is None]
        self._children.append(child)

    def _refresh(self) -> bool:
        color, title, detail = _status()
        self._indicator.set_icon_full(f"chrome-vpn-{color}", title)
        self._indicator.set_title(title)
        self._status_item.set_label(title)
        self._detail_item.set_label(detail)
        self._children = [process for process in self._children if process.poll() is None]
        return GLib.SOURCE_CONTINUE

    def _on_toggle(self, _item: Gtk.MenuItem) -> None:
        self._spawn(TOGGLE_COMMAND)
        GLib.timeout_add(750, self._refresh)

    def _on_check(self, _item: Gtk.MenuItem) -> None:
        self._spawn(CHECK_COMMAND)

    def _on_quit(self, _item: Gtk.MenuItem) -> None:
        Gtk.main_quit()


def main() -> int:
    try:
        ChromeMullvadTray()
        Gtk.main()
    except KeyboardInterrupt:
        return 0
    except Exception as exc:
        logging.exception("Chrome Mullvad indicator failed: %s", exc)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
