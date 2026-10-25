"""Exercise the managed Serena entry point without fetching a runtime."""
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from collections.abc import Generator
from contextlib import contextmanager
from textwrap import dedent

ROOT = pathlib.Path(__file__).resolve().parents[1]
BOOTSTRAP = ROOT / "scripts/serena-bootstrap.py"


@contextmanager
def cli_fixture() -> Generator[pathlib.Path, None, None]:
    with tempfile.TemporaryDirectory() as directory:
        root = pathlib.Path(directory)
        # Only the external SDK and CLI are doubles; the entry point is real.
        for package in ("mcp", "mcp/server", "mcp/server/fastmcp", "serena"):
            path = root / package
            path.mkdir(parents=True, exist_ok=True)
            _ = (path / "__init__.py").write_text("")
        _ = (root / "mcp/server/fastmcp/server.py").write_text(dedent("""\
            class Settings:
                ready = False
                @classmethod
                def model_rebuild(cls):
                    cls.ready = True
            """))
        _ = (root / "serena/cli.py").write_text(dedent("""\
            import json, sys
            from mcp.server.fastmcp.server import Settings
            def top_level(*, prog_name):
                if not Settings.ready:
                    raise RuntimeError('unresolved SDK settings')
                print(json.dumps({'program': prog_name, 'args': sys.argv[1:]}))
            """))
        yield root


def launch(root: pathlib.Path, *args: str) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["PYTHONPATH"] = str(root)
    return subprocess.run(
        [sys.executable, "-B", "-W", "error", str(BOOTSTRAP), *args],
        env=env, cwd=root, capture_output=True, text=True, timeout=10,
    )


class SerenaStartupTest(unittest.TestCase):
    def test_starts_cli_with_resolved_settings_and_preserves_literal_arguments(self) -> None:
        args = ["start-mcp-server", "--project", "/work/a b", "--context", "codex", "$(not-a-command)"]
        with cli_fixture() as root:
            result = launch(root, *args)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {"program": "serena", "args": args})
        self.assertEqual(result.stderr, "")

    def test_unexpected_sdk_warning_still_prevents_cli_startup(self) -> None:
        with cli_fixture() as root:
            _ = (root / "mcp/server/fastmcp/server.py").write_text(dedent("""\
                import warnings
                class Settings:
                    @classmethod
                    def model_rebuild(cls):
                        warnings.warn('SDK fixture warning', RuntimeWarning)
                """))
            result = launch(root, "start-mcp-server")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("RuntimeWarning: SDK fixture warning", result.stderr)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    _ = unittest.main()
