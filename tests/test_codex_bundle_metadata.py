import hashlib
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class BundleMetadataTest(unittest.TestCase):
    def test_refreshes_installed_hashes_and_preserves_upstream_receipts(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            voice = root / 'codex-resources/voice'
            (voice / 'lib').mkdir(parents=True)
            library = voice / 'lib/test.so'
            library.write_bytes(b'patched ELF')
            runtime = voice / 'runtime.json'
            runtime.write_text(json.dumps({'sourceSha256':'original-source', 'libraries':[
                {'path':'lib/test.so', 'sha256':'old-library'}]}))
            manifest = voice / 'manifest.json'
            manifest.write_text(json.dumps({'sha256':{'codex-resources/voice/lib/test.so':'old-library',
                                                     'codex-resources/voice/runtime.json':'old-runtime'}}))
            originals = {p: p.read_bytes() for p in [runtime, manifest]}
            result = subprocess.run([sys.executable, str(ROOT / 'scripts/fix-codex-manifests'), str(root)],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            data = json.loads(runtime.read_text())
            self.assertEqual(data['sourceSha256'],'original-source')
            self.assertEqual(data['libraries'][0]['sha256'],hashlib.sha256(library.read_bytes()).hexdigest())
            self.assertEqual(json.loads(manifest.read_text())['sha256']['codex-resources/voice/runtime.json'],hashlib.sha256(runtime.read_bytes()).hexdigest())
            verify = [sys.executable, str(ROOT / 'scripts/fix-codex-manifests'), str(root), '--verify']
            self.assertEqual(subprocess.run(verify, capture_output=True).returncode, 0)
            library.write_bytes(b'corrupted after refresh')
            self.assertNotEqual(subprocess.run(verify, capture_output=True).returncode, 0)
            for p, content in originals.items():
                self.assertEqual(p.with_suffix('.upstream.json').read_bytes(),content)


if __name__ == '__main__':
    unittest.main()
