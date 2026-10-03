#!/usr/bin/env python3
"""Read-only readiness checks, not an assistant transport or input controller."""

import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys


PROGRAMS = ("hyprctl", "wayland-info", "grim", "wtype", "wlrctl")
PROTOCOLS = (
    "zwlr_screencopy_manager_v1",
    "zwp_virtual_keyboard_manager_v1",
    "zwlr_virtual_pointer_manager_v1",
)
SAFE_COMPONENT = re.compile(r"[A-Za-z0-9_-][A-Za-z0-9_.-]{0,255}\Z")


def owned_path(path, kind, uid):
    """Reject missing paths, symlinks, other users, and shared runtime dirs."""
    try:
        info = path.lstat()
    except OSError:
        return False
    if info.st_uid != uid:
        return False
    if kind == "directory":
        return stat.S_ISDIR(info.st_mode) and info.st_mode & 0o077 == 0
    return stat.S_ISSOCK(info.st_mode)


def session_checks(env, uid):
    runtime = Path(env.get("XDG_RUNTIME_DIR", ""))
    display = env.get("WAYLAND_DISPLAY", "")
    instance = env.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    runtime_ok = runtime.is_absolute() and owned_path(runtime, "directory", uid)
    display_ok = bool(SAFE_COMPONENT.fullmatch(display))
    instance_ok = bool(SAFE_COMPONENT.fullmatch(instance))
    return {
        "wayland_session": env.get("XDG_SESSION_TYPE") == "wayland",
        "private_owned_runtime_directory": runtime_ok,
        "wayland_socket": bool(
            runtime_ok
            and display_ok
            and owned_path(runtime / display, "socket", uid)
        ),
        "hyprland_socket": bool(
            runtime_ok
            and instance_ok
            and owned_path(runtime / "hypr" / instance / ".socket.sock", "socket", uid)
        ),
    }


def query(argv, env):
    try:
        result = subprocess.run(
            argv,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    return result.stdout if result.returncode == 0 else None


def object_query(argv, env, run):
    result = run(argv, env)
    if result is None:
        return None
    try:
        value = json.loads(result)
    except (ValueError, TypeError):
        return None
    return value if isinstance(value, dict) else None


def probe(env=None, uid=None, which=shutil.which, run=query, check_session=session_checks):
    env = dict(os.environ if env is None else env)
    uid = os.getuid() if uid is None else uid
    programs = {name: which(name) for name in PROGRAMS}
    session = check_session(env, uid)
    report = {
        "schema_version": 1,
        "purpose": "read_only_local_readiness",
        "programs": {name: path is not None for name, path in programs.items()},
        "session": session,
        "protocols": {name: False for name in PROTOCOLS},
        "hyprland_version": None,
        "session_locked": None,
        "queries": {"version": False, "locked": False, "protocols": False},
        "local_prerequisites_detected": False,
        "assistant_transport": "not_tested",
        "screenshot_delivery": "not_tested",
        "input_delivery": "not_tested",
        "voice_routing": "not_tested",
    }
    # Never guess another session, import its environment, or connect when
    # ownership/session checks fail. Only the authorized executor may supply it.
    if not all(session.values()):
        return report

    if programs["hyprctl"]:
        version = object_query([programs["hyprctl"], "-j", "version"], env, run)
        if version is not None:
            # Emit only a version tag, never raw system information or errors.
            for field in ("version", "tag"):
                tag = version.get(field)
                if isinstance(tag, str) and re.fullmatch(r"v?\d+\.\d+\.\d+", tag):
                    report["hyprland_version"] = tag
                    report["queries"]["version"] = True
                    break
        locked = object_query([programs["hyprctl"], "-j", "locked"], env, run)
        if locked is not None and type(locked.get("locked")) is bool:
            report["queries"]["locked"] = True
            report["session_locked"] = locked["locked"]

    if programs["wayland-info"]:
        output = run([programs["wayland-info"]], env)
        if output is not None:
            advertised = set(re.findall(r"interface:\s*'([A-Za-z0-9_]+)'", output))
            report["queries"]["protocols"] = bool(advertised)
            report["protocols"] = {name: name in advertised for name in PROTOCOLS}

    report["local_prerequisites_detected"] = (
        all(report["programs"].values())
        and all(report["queries"].values())
        and all(report["protocols"].values())
        and report["session_locked"] is False
    )
    return report


def main():
    if len(sys.argv) != 1:
        print("Usage: hyprland-control-probe (read-only; no options)", file=sys.stderr)
        return 2
    report = probe()
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if report["local_prerequisites_detected"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
