"""Parse generated configs with the pinned compositor, without starting a session."""
import os
import pathlib
import subprocess
import sys
import tempfile

binary, helper_dir, *configs = sys.argv[1:]
with tempfile.TemporaryDirectory() as directory:
    root = pathlib.Path(directory)
    runtime = root / "runtime"
    runtime.mkdir(mode=0o700)
    env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime))
    for filename in configs:
        source = pathlib.Path(filename)
        config = root / source.name
        text = source.read_text()
        # Only relocate the installed helper for this isolated parse. Everything
        # else is the real Home Manager-generated config, including setup/hooks.
        installed_helper = "/home/jwilger/.config/hypr/?.lua;"
        assert text.count(installed_helper) == 1
        config.write_text(text.replace(installed_helper, helper_dir + "/?.lua;"))
        result = subprocess.run(
            [binary, "--verify-config", "--config", str(config)],
            env=env, text=True, capture_output=True,
        )
        output = result.stdout + result.stderr
        assert result.returncode == 0, f"{source.name}: exit {result.returncode}\n{output}"
        assert "config ok" in output, output
        print(f"ok - pinned Hyprland --verify-config: {source.name}")
