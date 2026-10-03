"""Offline contract tests. These never use the real graphical session."""

import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import patch


SOURCE = Path(__file__).resolve().parents[1] / "scripts" / "hyprland-control-probe.py"
SPEC = importlib.util.spec_from_file_location("probe", SOURCE)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ProbeTests(unittest.TestCase):
    def ready(self, overrides=None, missing=(), session_ok=True):
        responses = {
            ("hyprctl", "-j", "version"): json.dumps({"tag": "v0.55.4", "branch": "private"}),
            ("hyprctl", "-j", "locked"): '{"locked": false}',
            ("wayland-info",): "\n".join(
                f"interface: '{name}', version: 1, name: 9" for name in MODULE.PROTOCOLS
            ),
        }
        responses.update(overrides or {})
        calls = []

        def run(argv, env):
            calls.append(tuple(argv))
            return responses[tuple(argv)]

        report = MODULE.probe(
            env={}, uid=1000,
            which=lambda name: None if name in missing else name,
            run=run,
            check_session=lambda env, uid: {"safe_session": session_ok},
        )
        return report, calls

    def test_positive_result_does_not_claim_control_or_transport(self):
        report, calls = self.ready()
        self.assertTrue(report["local_prerequisites_detected"])
        self.assertEqual(report["hyprland_version"], "v0.55.4")
        for field in ("assistant_transport", "screenshot_delivery", "input_delivery", "voice_routing"):
            self.assertEqual(report[field], "not_tested")
        self.assertEqual(calls, [("hyprctl", "-j", "version"), ("hyprctl", "-j", "locked"), ("wayland-info",)])
        self.assertNotIn("private", json.dumps(report))

    def test_invalid_session_never_starts_a_client(self):
        report, calls = self.ready(session_ok=False)
        self.assertFalse(report["local_prerequisites_detected"])
        self.assertEqual(calls, [])

    def test_missing_programs_fail_readiness(self):
        for name in MODULE.PROGRAMS:
            with self.subTest(name=name):
                report, _ = self.ready(missing=(name,))
                self.assertFalse(report["local_prerequisites_detected"])

    def test_locked_unknown_and_malformed_lock_state_fail_closed(self):
        for value in ('{"locked": true}', '{"locked": "false"}', '{}', 'null', '[]', 'bad', None):
            with self.subTest(value=value):
                report, _ = self.ready({("hyprctl", "-j", "locked"): value})
                self.assertFalse(report["local_prerequisites_detected"])

    def test_missing_protocol_and_failed_queries_fail_readiness(self):
        for output in (None, "", "no interfaces", "interface: 'wl_compositor'"):
            report, _ = self.ready({("wayland-info",): output})
            self.assertFalse(report["local_prerequisites_detected"])
        report, _ = self.ready({("hyprctl", "-j", "version"): "bad"})
        self.assertFalse(report["local_prerequisites_detected"])

    def test_raw_command_output_is_never_emitted(self):
        report, _ = self.ready({("hyprctl", "-j", "version"): '{"version":"private-token","hostname":"secret"}', ("wayland-info",): "private window title"})
        self.assertNotIn("private-token", json.dumps(report))
        self.assertNotIn("secret", json.dumps(report))
        self.assertNotIn("private window title", json.dumps(report))

    def test_unknown_or_invalid_version_fails_readiness(self):
        for version in ({}, {"version": 55}, {"version": "private-token"}, {"tag": None}, {"version": "0.55.4\n"}):
            with self.subTest(version=version):
                report, _ = self.ready({("hyprctl", "-j", "version"): json.dumps(version)})
                self.assertIsNone(report["hyprland_version"])
                self.assertFalse(report["queries"]["version"])
                self.assertFalse(report["local_prerequisites_detected"])
        report, _ = self.ready({("hyprctl", "-j", "version"): '{"version":"0.55.4"}'})
        self.assertEqual(report["hyprland_version"], "0.55.4")
        self.assertTrue(report["local_prerequisites_detected"])

    def test_query_is_bounded_read_only_subprocess(self):
        with patch.object(MODULE.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "ok")) as run:
            self.assertEqual(MODULE.query(["wayland-info"], {}), "ok")
            self.assertEqual(run.call_args.kwargs["timeout"], 5)
            self.assertNotIn("shell", run.call_args.kwargs)
            self.assertEqual(run.call_args.kwargs["stdin"], subprocess.DEVNULL)
        for error in (OSError(), subprocess.TimeoutExpired("test", 5)):
            with patch.object(MODULE.subprocess, "run", side_effect=error):
                self.assertIsNone(MODULE.query(["wayland-info"], {}))
        with patch.object(MODULE.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, "private error")):
            self.assertIsNone(MODULE.query(["wayland-info"], {}))


class SessionTests(unittest.TestCase):
    def test_session_ownership_paths_and_symlinks(self):
        with tempfile.TemporaryDirectory() as temp:
            runtime = Path(temp)
            runtime.chmod(0o700)
            hypr = runtime / "hypr" / "test_123_456"
            hypr.mkdir(parents=True)
            sockets = (runtime / "wayland-0", hypr / ".socket.sock")
            for path in sockets:
                path.touch()
            real_lstat = Path.lstat

            def synthetic_socket_lstat(path):
                info = real_lstat(path)
                if path in sockets:
                    values = list(info)
                    values[0] = stat.S_IFSOCK | 0o600
                    return os.stat_result(values)
                return info

            # No real sockets or live graphical clients, including in a build
            # sandbox where socket creation is intentionally unavailable.
            with patch.object(Path, "lstat", synthetic_socket_lstat):
                env = {"XDG_SESSION_TYPE": "wayland", "XDG_RUNTIME_DIR": temp, "WAYLAND_DISPLAY": "wayland-0", "HYPRLAND_INSTANCE_SIGNATURE": "test_123_456"}
                uid = runtime.stat().st_uid
                self.assertTrue(all(MODULE.session_checks(env, uid).values()))
                self.assertFalse(all(MODULE.session_checks(env, uid + 1).values()))
                for key in env:
                    self.assertFalse(all(MODULE.session_checks({k: v for k, v in env.items() if k != key}, uid).values()))
                for key in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
                    for value in ("../other", "/tmp/other", ".", ".."):
                        self.assertFalse(all(MODULE.session_checks(env | {key: value}, uid).values()))
                (runtime / "alias").symlink_to(runtime / "wayland-0")
                self.assertFalse(MODULE.session_checks(env | {"WAYLAND_DISPLAY": "alias"}, uid)["wayland_socket"])
                runtime.chmod(0o750)
                self.assertFalse(MODULE.session_checks(env, uid)["private_owned_runtime_directory"])


if __name__ == "__main__":
    unittest.main()
