"""Reject invalid upstream artifacts before altering a package pin."""
import hashlib
import io
import json
import pathlib
import subprocess
import sys
import tarfile
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
NAME = 'codex-package-x86_64-unknown-linux-musl.tar.gz'


class UpdaterTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name)
        self.release = self.root / 'release.json'
        self.release.write_text(json.dumps({'tag_name': 'rust-v1.2.3', 'prerelease': False, 'draft': False,
                                           'assets': [{'name': name, 'browser_download_url':
                                                       f'https://github.com/openai/codex/releases/download/rust-v1.2.3/{name}'}
                                                      for name in [NAME, 'codex-package_SHA256SUMS']]}))
        self.archive = self.root / 'bundle.tar.gz'
        self.build_archive()
        self.module = self.root / 'package.nix'
        self.original = '{\n  version = "0.1.0";\n    hash = "old";\n}\n'
        self.module.write_text(self.original)

    def build_archive(self, complete=True):
        with tarfile.open(self.archive, 'w:gz') as archive:
            files = {'codex-package.json': json.dumps({'layoutVersion': 1, 'version': '1.2.3',
                     'target': 'x86_64-unknown-linux-musl', 'variant': 'codex', 'entrypoint': 'bin/codex',
                     'resourcesDir': 'codex-resources', 'pathDir': 'codex-path'}).encode(), 'bin/codex': b'fake executable'}
            if complete:
                files['bin/codex-code-mode-host'] = b'fake companion'
            for name, data in files.items():
                info = tarfile.TarInfo(name)
                info.size = len(data)
                info.mode = 0o755
                archive.addfile(info, io.BytesIO(data))
        digest = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        self.checksums = self.root / 'SHA256SUMS'
        self.checksums.write_text(f'{digest}  {NAME}\n')

    def run_update(self):
        return subprocess.run([sys.executable, str(ROOT / 'scripts/update-codex'), '--release-json', str(self.release),
                               '--archive', str(self.archive), '--checksums', str(self.checksums),
                               '--module', str(self.module)], capture_output=True, text=True)

    def test_updates_coupled_pin_and_is_noop_on_same_artifact(self):
        result = self.run_update()
        self.assertEqual(result.returncode, 0, result.stderr)
        content = self.module.read_text()
        self.assertIn('version = "1.2.3";', content)
        self.assertIn('hash = "sha256-', content)
        before = self.module.stat().st_mtime_ns
        self.assertEqual(self.run_update().returncode, 0)
        self.assertEqual(self.module.stat().st_mtime_ns, before)

    def test_checksum_mismatch_leaves_pin_unchanged(self):
        self.checksums.write_text(f'{"0" * 64}  {NAME}\n')
        self.assertNotEqual(self.run_update().returncode, 0)
        self.assertEqual(self.module.read_text(), self.original)

    def test_incomplete_bundle_leaves_pin_unchanged(self):
        self.build_archive(complete=False)
        self.assertNotEqual(self.run_update().returncode, 0)
        self.assertEqual(self.module.read_text(), self.original)

    def test_unstable_or_mismatched_release_is_rejected(self):
        for change in [{'prerelease': True}, {'tag_name': 'rust-v1.2.3-rc.1'}, {'tag_name': 'rust-v9.9.9'}]:
            with self.subTest(change=change):
                original = json.loads(self.release.read_text())
                changed = dict(original, **change)
                self.release.write_text(json.dumps(changed))
                self.assertNotEqual(self.run_update().returncode, 0)
                self.assertEqual(self.module.read_text(), self.original)
                self.release.write_text(json.dumps(original))


if __name__ == '__main__':
    unittest.main()
