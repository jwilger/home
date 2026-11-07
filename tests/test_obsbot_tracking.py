"""Verify camera-session recovery without waking an idle camera."""

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock


source = Path(os.environ.get("OBSBOT_TRACKING_SOURCE", Path(__file__).parents[1] / "modules/home/desktop/obsbot-tracking.py"))
spec = importlib.util.spec_from_file_location("obsbot_tracking", source)
obsbot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(obsbot)
CLIENT = frozenset({("/dev/video6", "123", "8")})


class ResumeTracking(unittest.TestCase):
    def setUp(self):
        self.resume = obsbot.TrackingResume()
        self.status = Mock(return_value=(True, "Static"))
        self.restore = Mock()

    def poll(self, clients, now):
        self.resume.poll(clients, now, self.status, self.restore)

    def test_idle_never_opens_or_polls_camera(self):
        for now in (0, 2, 120, 600):
            self.poll(frozenset(), now)
        self.status.assert_not_called()
        self.restore.assert_not_called()

    def test_sleeping_camera_is_not_woken(self):
        self.status.return_value = (False, "Static")
        self.poll(CLIENT, 0)
        self.restore.assert_not_called()
        self.status.return_value = (True, "Static")
        self.poll(CLIENT, 2)
        self.restore.assert_called_once()

    def test_restores_after_long_idle_and_reopen(self):
        self.poll(CLIENT, 0)
        self.status.return_value = (True, "Normal Tracking")
        self.poll(CLIENT, 2)
        self.poll(frozenset(), 4)
        self.poll(frozenset(), 600)
        self.status.return_value = (True, "Static")
        self.poll(CLIENT, 602)
        self.assertEqual(self.restore.call_count, 2)

    def test_manual_static_during_same_session_is_respected(self):
        self.status.return_value = (True, "Normal Tracking")
        self.poll(CLIENT, 0)
        self.status.return_value = (True, "Static")
        self.poll(CLIENT, 2)
        self.restore.assert_not_called()
        self.assertEqual(self.status.call_count, 1)

    def test_preserves_existing_close_up_mode(self):
        self.status.return_value = (True, "Close-up")
        self.poll(CLIENT, 0)
        self.poll(CLIENT, 2)
        self.restore.assert_not_called()

    def test_retry_window_is_bounded(self):
        for now in range(0, 40, 2):
            self.poll(CLIENT, now)
        self.assertEqual(self.restore.call_count, 15)
        self.assertEqual(self.status.call_count, 15)

    def test_temporary_unavailable_status_can_recover(self):
        self.status.return_value = None
        self.poll(CLIENT, 0)
        self.restore.assert_not_called()
        self.status.return_value = (True, "Static")
        self.poll(CLIENT, 2)
        self.restore.assert_called_once()

    def test_laptop_resume_with_same_client_is_rechecked(self):
        self.status.return_value = (True, "Normal Tracking")
        self.poll(CLIENT, 0)
        self.status.return_value = (True, "Static")
        self.poll(CLIENT, 602)
        self.restore.assert_called_once()


class ClientDiscovery(unittest.TestCase):
    def test_only_connected_obsbot_capture_clients_are_selected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            sysfs, proc = root / "sys", root / "proc"
            sysfs.mkdir()
            proc.mkdir()
            for name, card, index in [
                ("video6", "OBSBOT Tiny 2 Lite: OBSBOT Tiny", "0"),
                ("video7", "OBSBOT Tiny 2 Lite: OBSBOT Tiny", "1"),
                ("video0", "Integrated Camera", "0"),
            ]:
                path = sysfs / name
                path.mkdir()
                (path / "name").write_text(card)
                (path / "index").write_text(index)
            fds = proc / "123" / "fd"
            fds.mkdir(parents=True)
            (fds.parent / "exe").symlink_to("/usr/bin/ffplay")
            for fd, target in [("8", "/dev/video6"), ("9", "/dev/video7"), ("10", "/dev/video0")]:
                (fds / fd).symlink_to(target)
            self.assertEqual(obsbot.camera_clients(sysfs, proc), CLIENT)
            (fds.parent / "exe").unlink()
            (fds.parent / "exe").symlink_to("/nix/store/test/bin/tiny4linux-cli")
            self.assertEqual(obsbot.camera_clients(sysfs, proc), frozenset())
            (fds.parent / "exe").unlink()
            (fds.parent / "exe").symlink_to("/usr/bin/ffplay")
            (fds / "8").unlink()
            self.assertEqual(obsbot.camera_clients(sysfs, proc), frozenset())
            # Ambiguous multiple matching cameras must not control the wrong one.
            other = sysfs / "video8"
            other.mkdir()
            (other / "name").write_text("OBSBOT Tiny 2")
            (other / "index").write_text("0")
            (fds / "8").symlink_to("/dev/video6")
            self.assertEqual(obsbot.camera_clients(sysfs, proc), frozenset())


if __name__ == "__main__":
    unittest.main()
