"""Exercise generated Home Manager configuration through a real terminal boundary.

Run via nix build .#checks.x86_64-linux.tmux-clipboard -L. The PTY represents
WezTerm; it captures OSC 52 rather than allowing it near the real clipboard.
"""

import base64
import errno
import fcntl
import os
import pty
import re
import select
import shlex
import struct
import subprocess
import tempfile
import termios
import time
import unittest
from pathlib import Path


class ClipboardTerminal(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.TemporaryDirectory(prefix="clipboard-")
        self.addCleanup(self.root.cleanup)
        self.directory = Path(self.root.name)
        self.socket = str(self.directory / "socket")
        self.host_log = self.directory / "host-clipboard"
        bin_dir = self.directory / "bin"
        bin_dir.mkdir()
        for name in ("wl-copy", "xclip", "xsel", "pbcopy"):
            script = bin_dir / name
            script.write_text(f"#!/bin/sh\nprintf invoked >> {shlex.quote(str(self.host_log))}\ncat >/dev/null\n")
            script.chmod(0o755)
        self.env = {
            **os.environ,
            "HOME": str(self.directory),
            "XDG_CONFIG_HOME": str(self.directory / "config"),
            "TERM": "xterm-256color",
            "PATH": f"{bin_dir}:{os.environ['PATH']}",
            # Simulate a stale graphical environment in a persistent server.
            "WAYLAND_DISPLAY": "clipboard-test-no-compositor",
            "DISPLAY": ":999",
        }
        self.env.pop("TMUX", None)
        self.env.pop("TMUX_PANE", None)
        self.tmux("-f", os.environ["TMUX_CLIPBOARD_CONFIG"], "new-session", "-d", "-s", "test", "-x", "100", "-y", "24", "sleep 300")
        self.addCleanup(self.stop_server)
        self.attach()

    def tmux(self, *args):
        result = subprocess.run(
            ["tmux", "-S", self.socket, *args], env=self.env,
            capture_output=True, timeout=10,
        )
        if result.returncode:
            self.fail(f"tmux {args!r} failed ({result.returncode}): {result.stderr.decode(errors='replace')}")
        return result.stdout

    def stop_server(self):
        subprocess.run(["tmux", "-S", self.socket, "kill-server"], env=self.env, capture_output=True, timeout=10)

    def attach(self):
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))

        def controlling_terminal():
            os.setsid()
            fcntl.ioctl(0, termios.TIOCSCTTY, 0)

        self.client = subprocess.Popen(
            ["tmux", "-S", self.socket, "attach-session", "-t", "test"],
            env=self.env, stdin=slave, stdout=slave, stderr=slave,
            preexec_fn=controlling_terminal,
        )
        os.close(slave)
        self.master = master
        self.addCleanup(self.close_client, self.client, master)
        self.output = b""
        self.wait_for(lambda: bool(self.tmux("list-clients")), "client attachment")
        self.drain(0.2)

    @staticmethod
    def close_client(client, master):
        if client.poll() is None:
            client.terminate()
            client.wait(timeout=10)
        os.close(master)

    def drain(self, duration=0.1):
        deadline = time.monotonic() + duration
        while time.monotonic() < deadline:
            ready, _, _ = select.select([self.master], [], [], max(0, deadline - time.monotonic()))
            if ready:
                try:
                    self.output += os.read(self.master, 65536)
                except OSError:
                    break

    def wait_for(self, predicate, description):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            self.drain(0.05)
            if predicate():
                return
        screen = self.tmux("capture-pane", "-p").decode(errors="replace")
        self.fail(f"Timed out waiting for {description}; screen:\n{screen}\nterminal tail: {self.output[-200:]!r}")

    def clipboard_payloads(self):
        return [
            base64.b64decode(match)
            for match in re.findall(rb"\x1b\]52;[cp]*;([A-Za-z0-9+/=]*)(?:\x07|\x1b\\)", self.output)
        ]

    def pane_command(self, command):
        self.tmux("respawn-pane", "-k", command)

    def select_line(self, text):
        self.pane_command(f"printf '%s\\n' {shlex.quote(text)}; exec sleep 300")
        self.wait_for(lambda: text.encode() in self.tmux("capture-pane", "-p"), "pane text")
        self.tmux("copy-mode")
        self.tmux("send-keys", "-X", "history-top")
        self.tmux("send-keys", "-X", "start-of-line")
        self.tmux("send-keys", "-X", "begin-selection")
        self.tmux("send-keys", "-X", "end-of-line")
        self.output = b""

    def assert_clipboard(self, expected):
        self.wait_for(lambda: expected in self.clipboard_payloads(), f"OSC 52 copy of {expected!r}")
        self.assertFalse(self.host_log.exists(), "Copy invoked a server-local clipboard tool")

    def test_copy_mode_y_targets_the_attached_terminal_not_the_host(self):
        self.select_line("terminal-owned-copy")
        os.write(self.master, b"y")
        self.assert_clipboard(b"terminal-owned-copy")

    def test_reload_replaces_old_host_clipboard_bindings_without_losing_the_session(self):
        pane = self.tmux("display-message", "-p", "#{pane_id}")
        self.tmux("set-option", "-s", "copy-command", "wl-copy")
        for table, key in (("copy-mode-vi", "y"), ("copy-mode-vi", "MouseDragEnd1Pane"), ("copy-mode", "MouseDragEnd1Pane")):
            self.tmux("bind-key", "-T", table, key, "send-keys", "-X", "copy-pipe-and-cancel", "wl-copy")
        legacy_command = f"printf legacy >> {shlex.quote(str(self.host_log))}"
        for key in ("y", "Y"):
            self.tmux("bind-key", "-T", "prefix", key, "run-shell", legacy_command)
        for table in ("copy-mode-vi", "copy-mode"):
            for key in ("Y", "M-y", "!") + (("y",) if table == "copy-mode" else ()):
                self.tmux("bind-key", "-T", table, key, "send-keys", "-X", "copy-pipe-and-cancel", legacy_command)
        self.tmux("source-file", os.environ["TMUX_CLIPBOARD_CONFIG"])
        self.assertEqual(pane, self.tmux("display-message", "-p", "#{pane_id}"))
        for key in (b"y", b"Y"):
            os.write(self.master, b"\x01" + key)
            self.drain(0.2)
            self.assertFalse(self.host_log.exists(), "Reload retained a legacy prefix copy binding")
        for mode in ("vi", "emacs"):
            self.tmux("set-window-option", "mode-keys", mode)
            for key in (b"Y", b"\x1by", b"!") + ((b"y",) if mode == "emacs" else ()):
                self.select_line("retired-copy-shortcut")
                self.tmux("set-buffer", "previous-buffer")
                os.write(self.master, key)
                self.drain(0.2)
                self.assertFalse(self.host_log.exists(), "Reload retained a legacy copy-mode binding")
                self.assertEqual(b"previous-buffer", self.tmux("show-buffer"))
                self.tmux("send-keys", "-X", "cancel")
        self.tmux("set-window-option", "mode-keys", "vi")
        self.select_line("reloaded-keyboard-copy")
        os.write(self.master, b"y")
        self.assert_clipboard(b"reloaded-keyboard-copy")
        self.mouse_copy()

    def test_mouse_drag_release_copies_to_the_terminal(self):
        self.mouse_copy()

    def mouse_copy(self):
        self.pane_command("printf mouse-copy-test; exec sleep 300")
        self.wait_for(lambda: b"mouse-copy-test" in self.tmux("capture-pane", "-p"), "mouse selection text")
        self.output = b""
        # SGR left-button press, drag to column 15, release on the first row.
        os.write(self.master, b"\x1b[<0;1;1M\x1b[<32;2;1M")
        self.wait_for(lambda: self.tmux("display-message", "-p", "#{pane_in_mode}").strip() == b"1", "mouse copy mode")
        os.write(self.master, b"\x1b[<32;15;1M\x1b[<0;15;1m")
        self.assert_clipboard(b"mouse-copy-test")

    def test_plain_application_copy_reaches_the_terminal(self):
        text = b"plain application copy"
        payload = base64.b64encode(text).decode()
        sequence = f"\x1b]52;c;{payload}\x07"
        self.output = b""
        self.pane_command(f"printf %s {shlex.quote(sequence)}; exec sleep 300")
        self.assert_clipboard(text)

    def test_reattached_terminal_receives_copy_and_can_paste(self):
        first_master = self.master
        first_client = self.client
        self.tmux("detach-client")
        first_client.wait(timeout=10)
        self.attach()
        self.select_line("after-reattach")
        os.write(self.master, b"y")
        self.assert_clipboard(b"after-reattach")
        # A detached terminal must not receive the new clipboard write.
        first_output = b""
        try:
            while select.select([first_master], [], [], 0)[0]:
                chunk = os.read(first_master, 65536)
                if not chunk:
                    break
                first_output += chunk
        except OSError as error:
            # Linux PTYs report EIO once the detached client's slave closes.
            if error.errno != errno.EIO:
                raise
        self.assertNotIn(base64.b64encode(b"after-reattach"), first_output)
        pasted = self.directory / "pasted"
        self.pane_command(f"stty -echo; printf ready-to-paste; cat > {shlex.quote(str(pasted))}")
        self.wait_for(lambda: b"ready-to-paste" in self.tmux("capture-pane", "-p"), "paste receiver")
        # This is what WezTerm's paste action delivers to a foreground process.
        os.write(self.master, "paste café ✓\n".encode())
        self.wait_for(lambda: pasted.exists() and pasted.read_text() == "paste café ✓\n", "pasted bytes")

    def test_helix_system_yank_targets_the_terminal_with_a_stale_display(self):
        text = "Helix café ✓\n"
        document = self.directory / "copy.txt"
        document.write_text(text)
        config = shlex.quote(os.environ["HELIX_CLIPBOARD_CONFIG"])
        self.pane_command(f"hx -c {config} {shlex.quote(str(document))}")
        self.wait_for(lambda: b"Helix" in self.tmux("capture-pane", "-p"), "Helix document")
        self.output = b""
        os.write(self.master, b"% y")
        self.assert_clipboard(text.encode())

    def test_lazygit_copy_preserves_unicode_and_shell_metacharacters(self):
        text = "café %s $(touch INJECTION) `touch INJECTION2` 'quoted' \\ path"
        repo = self.directory / "repo"
        repo.mkdir()
        subprocess.run(["git", "init", "-q", str(repo)], env=self.env, check=True)
        subprocess.run([
            "git", "-C", str(repo), "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
            "commit", "-q", "--allow-empty", "-m", text,
        ], env=self.env, check=True)
        config = shlex.quote(os.environ["LAZYGIT_CLIPBOARD_CONFIG"])
        self.pane_command(f"cd {shlex.quote(str(repo))}; lazygit --use-config-file {config}")
        self.wait_for(lambda: b"Thanks for using lazygit" in self.tmux("capture-pane", "-p"), "Lazygit welcome")
        os.write(self.master, b"\x1b")
        self.wait_for(lambda: b"Thanks for using lazygit" not in self.tmux("capture-pane", "-p"), "welcome dismissal")
        os.write(self.master, b"4y")
        self.wait_for(lambda: b"Copy" in self.tmux("capture-pane", "-p"), "commit copy menu")
        self.output = b""
        os.write(self.master, b"m")
        self.assert_clipboard(text.encode())
        self.assertFalse((repo / "INJECTION").exists())
        self.assertFalse((repo / "INJECTION2").exists())

    def test_tmux_wrapped_application_copy_reaches_the_terminal(self):
        payload = base64.b64encode("wrapped ✓".encode()).decode()
        sequence = f"\x1bPtmux;\x1b\x1b]52;c;{payload}\x07\x1b\\"
        self.output = b""
        self.pane_command(f"printf %s {shlex.quote(sequence)}; exec sleep 300")
        self.assert_clipboard("wrapped ✓".encode())


if __name__ == "__main__":
    unittest.main()
