"""Restore tracking when an application starts using the OBSBOT camera.

Only inspect process file-descriptor links while idle: opening or polling the
camera itself must not interfere with its privacy sleep timer.
"""

import argparse
import os
from pathlib import Path
import re
import subprocess
import time


def camera_clients(sysfs=Path("/sys/class/video4linux"), proc=Path("/proc")):
    nodes = []
    try:
        for entry in sysfs.iterdir():
            try:
                if (entry / "name").read_text().startswith("OBSBOT Tiny 2") and (
                    entry / "index"
                ).read_text().strip() == "0":
                    nodes.append(f"/dev/{entry.name}")
            except OSError:
                continue
    except OSError:
        return frozenset()
    # Tiny4Linux controls the first matching camera; do not guess with several.
    if len(nodes) != 1:
        return frozenset()

    clients = set()
    for process in proc.iterdir():
        try:
            if not process.name.isdecimal() or process.stat().st_uid != os.getuid():
                continue
            # Control-only Tiny4Linux commands must not look like a new call,
            # especially when the user explicitly selects Static tracking.
            if Path(os.readlink(process / "exe")).name in {
                "t4l", "tiny4linux-cli", "tiny4linux-gui", ".tiny4linux-gui-wrapped"
            }:
                continue
            for fd in (process / "fd").iterdir():
                try:
                    if os.readlink(fd) == nodes[0]:
                        clients.add((nodes[0], process.name, fd.name))
                except OSError:
                    continue
        except OSError:
            continue
    return frozenset(clients)


def camera_status(t4l):
    try:
        result = subprocess.run(
            [t4l, "info"], capture_output=True, text=True, timeout=5, check=False
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    mode = re.search(r"AI Mode: ([^\n]+)", result.stdout)
    if result.returncode or not mode:
        return None
    return "Sleep Mode: Awake" in result.stdout, mode.group(1).strip()


class TrackingResume:
    def __init__(self):
        self.clients = frozenset()
        self.deadline = 0
        self.last_poll = None

    def poll(self, clients, now, status, restore):
        resumed = self.last_poll is not None and now - self.last_poll > 10
        started = bool(clients - self.clients)
        self.clients, self.last_poll = clients, now
        if not clients:
            self.deadline = 0
            return
        if started or resumed:
            self.deadline = now + 30
        if now >= self.deadline:
            return
        current = status()
        if current is None:
            return
        awake, mode = current
        if not awake:
            return
        if mode not in ("Static", "Unknown"):
            self.deadline = 0
        elif mode == "Static":
            restore()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--t4l", required=True)
    args = parser.parse_args()
    resume = TrackingResume()

    def restore():
        print("Restoring normal OBSBOT tracking for a new camera session", flush=True)
        try:
            subprocess.run([args.t4l, "tracking", "normal"], timeout=5, check=False)
        except (OSError, subprocess.TimeoutExpired) as error:
            print(f"Tracking command unavailable: {error}", flush=True)

    while True:
        # BOOTTIME includes laptop suspend, so an existing client can resume too.
        now = time.clock_gettime(time.CLOCK_BOOTTIME)
        resume.poll(camera_clients(), now, lambda: camera_status(args.t4l), restore)
        time.sleep(2)


if __name__ == "__main__":
    main()
