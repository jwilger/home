"""Exercise the actual executor-copy patch against read-only package-like trees."""
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
COPY = 'await j.default.cp(n.cwd,e,{recursive:!0})'
FIXTURE = ('const j={default:fs};async function ese({executorPluginRoot:e,resourcesPath:t})'
           '{let n=await Rc({useWsl:!1,resourcesPath:t});return n==null?null:('
           + COPY + ',process.platform!==`win32`&&(n.command=e),'
           'await j.default.writeFile(e+`/.mcp.json`,`updated`),n)}')


class ExecutorPatchTest(unittest.TestCase):
    def patch(self, bundle):
        return subprocess.run([sys.executable, str(ROOT/'scripts/patch-chatgpt-executor'),
                               str(bundle)], text=True, capture_output=True)

    def test_copy_and_refresh_readonly_private_tree(self):
        with tempfile.TemporaryDirectory() as tmp:
            bundle = pathlib.Path(tmp)/'main-test.js'
            bundle.write_text(FIXTURE)
            patched = self.patch(bundle)
            self.assertEqual(patched.returncode, 0, patched.stderr)
            harness = r'''
const fs=require('node:fs/promises'),path=require('node:path');
async function main(){
 const root=process.argv[2],src=path.join(root,'source'),dst=path.join(root,'private');
 await fs.mkdir(path.join(src,'.codex-plugin'),{recursive:true});
 await fs.writeFile(path.join(src,'.codex-plugin/plugin.json'),'manifest');
 await fs.writeFile(path.join(src,'.mcp.json'),'original');
 for(const p of ['.codex-plugin/plugin.json','.mcp.json'])await fs.chmod(path.join(src,p),0o444);
 for(const p of ['.codex-plugin',''])await fs.chmod(path.join(src,p),0o555);
 const Rc=async()=>({cwd:src,command:'node'});
 const ese=eval('('+process.env.PATCHED.replace('const j={default:fs};','')+')');
 // The first launch must rewrite the copied manifest; a subsequent launch
 // must overwrite a destination left read-only by an older package.
 await ese({executorPluginRoot:dst});
 for(const p of ['.mcp.json','.codex-plugin/plugin.json','.codex-plugin','']){
   if(!((await fs.stat(path.join(dst,p))).mode&0o200))throw Error('not owner writable: '+p);
 }
 for(const p of ['.mcp.json','.codex-plugin/plugin.json'])await fs.chmod(path.join(dst,p),0o444);
 for(const p of ['.codex-plugin',''])await fs.chmod(path.join(dst,p),0o555);
 await ese({executorPluginRoot:dst});
 if(await fs.readFile(path.join(dst,'.mcp.json'),'utf8')!=='updated')throw Error('rewrite failed');
 // Reject symlinks before copy/write can follow them, including ancestors.
 const external=path.join(root,'external');await fs.writeFile(external,'keep');await fs.chmod(external,0o444);
 async function rejects(destination){
   let rejected=false;try{await ese({executorPluginRoot:destination})}catch(e){rejected=/Unsafe executor plugin/.test(e.message)}
   if(!rejected)throw Error('symlink not rejected: '+destination);
 }
 for(const name of ['untouched-link','.mcp.json']){
   const link=path.join(dst,name);await fs.rm(link,{force:true});await fs.symlink(external,link);
   await rejects(dst);await fs.unlink(link);
 }
 const alias=path.join(root,'alias');await fs.symlink(dst,alias);
 await rejects(alias);await rejects(path.join(alias,'child'));
 await fs.chmod(src,0o755);await fs.symlink(external,path.join(src,'source-link'));
 await rejects(dst);await fs.unlink(path.join(src,'source-link'));await fs.chmod(src,0o555);
 if((await fs.stat(external)).mode&0o200)throw Error('followed symlink');
 if(await fs.readFile(external,'utf8')!=='keep')throw Error('overwrote external file');
 if((await fs.stat(src)).mode&0o200)throw Error('modified source');
 // Permit fixture cleanup even on failure in a root-run test environment.
 for(const p of ['.codex-plugin',''])await fs.chmod(path.join(src,p),0o755);
}
main().catch(e=>{console.error(e);process.exitCode=1});
'''
            import os
            env = dict(os.environ, PATCHED=bundle.read_text())
            # The fixture refers to the same fs alias used in the bundle.
            harness = harness.replace('const Rc=async()', 'const j={default:fs};const Rc=async()')
            result = subprocess.run(['node', '-e', harness, 'fixture', tmp],
                                    env=env, text=True, capture_output=True)
            # Always restore directory permissions for TemporaryDirectory cleanup.
            for base, _, _files in os.walk(tmp):
                os.chmod(base, pathlib.Path(base).stat().st_mode | 0o200)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_missing_or_ambiguous_copy_site_without_writing(self):
        for source in ['unrelated', FIXTURE+FIXTURE,
                       FIXTURE.replace('executorPluginRoot', 'unrelatedRoot')]:
            with self.subTest(source=source), tempfile.TemporaryDirectory() as tmp:
                bundle = pathlib.Path(tmp)/'main-test.js'
                bundle.write_text(source)
                self.assertNotEqual(self.patch(bundle).returncode, 0)
                self.assertEqual(bundle.read_text(), source)


if __name__ == '__main__':
    unittest.main()
