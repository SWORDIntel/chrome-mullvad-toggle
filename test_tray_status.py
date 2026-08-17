from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path
from unittest.mock import patch

MODULE_PATH = Path(__file__).with_name("chrome-mullvad-tray.py")
SPEC = importlib.util.spec_from_file_location("chrome_mullvad_tray", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Unable to load {MODULE_PATH}")
TRAY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TRAY)


class TrayStatusTests(unittest.TestCase):
    def test_stopped_is_red(self) -> None:
        with patch.object(TRAY, "_chrome_pids", return_value=set()):
            self.assertEqual(TRAY._status()[0], "red")

    def test_mullvad_is_green(self) -> None:
        with (
            patch.object(TRAY, "_chrome_pids", return_value={101, 102}),
            patch.object(TRAY, "_explicitly_excluded_pids", return_value=set()),
            patch.object(TRAY, "_pid_is_excluded", return_value=False),
        ):
            self.assertEqual(TRAY._status()[0], "green")

    def test_direct_is_red(self) -> None:
        with (
            patch.object(TRAY, "_chrome_pids", return_value={101, 102}),
            patch.object(TRAY, "_explicitly_excluded_pids", return_value=set()),
            patch.object(TRAY, "_pid_is_excluded", return_value=True),
        ):
            self.assertEqual(TRAY._status()[0], "red")

    def test_mixed_is_amber(self) -> None:
        with (
            patch.object(TRAY, "_chrome_pids", return_value={101, 102}),
            patch.object(TRAY, "_explicitly_excluded_pids", return_value=set()),
            patch.object(TRAY, "_pid_is_excluded", side_effect=lambda pid, _explicit: pid == 101),
        ):
            self.assertEqual(TRAY._status()[0], "amber")


if __name__ == "__main__":
    unittest.main()
