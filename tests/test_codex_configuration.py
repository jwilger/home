"""Exercise the writable Home Manager/agent configuration boundary."""
import json
import pathlib
import subprocess
import sys
import tempfile
import tomllib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class ConfigurationTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = pathlib.Path(self.tmp.name)
        self.codex = self.home / '.codex'
        self.codex.mkdir()
        self.defaults = self.home / 'defaults.json'
        self.defaults.write_text(json.dumps({
            'settings': {'model': 'test-model', 'features': {'hooks': True, 'apps': True, 'remote_plugin': True},
                         'apps': {'_default': {'enabled': True}},
                         'mcp_servers': {'serena': {'command': '/managed/serena', 'args': ['--context', 'codex']}}},
            'retired_features': ['code_mode', 'code_mode_only'],
            'rtk_command': '/managed/rtk hook codex',
            'serena_settings': {'web_dashboard_open_on_launch': False},
            'serena_trust': [str(self.home / 'src') + '/**'],
            'codex_executable': '/managed/codex',
        }))

    def reconcile(self):
        return subprocess.run([sys.executable, str(ROOT / 'scripts/reconcile-codex'), '--home', str(self.home),
                               '--defaults', str(self.defaults)], capture_output=True, text=True)

    def test_lean_cli_disables_global_integrations_preserving_project_and_desktop(self):
        defaults = json.loads(self.defaults.read_text())
        defaults['lean_cli'] = True
        self.defaults.write_text(json.dumps(defaults))
        config = self.codex / 'config.toml'
        config.write_text('[plugins."local@example"]\nenabled = true\n'
                          '[mcp_servers.custom]\ncommand = "/local/mcp"\n'
                          '[mcp_servers.hindsight]\ncommand = "node"\n'
                          '[features]\nmulti_agent = true\n')
        desktop = self.home / '.codex-chatgpt/config.toml'
        desktop.parent.mkdir()
        desktop.write_text('desktop sentinel')
        project = self.home / 'src/project/.codex/config.toml'
        project.parent.mkdir(parents=True)
        project.write_text('project sentinel')
        companion = self.home / '.agents/skills/hindsight-coding-agent/SKILL.md'
        companion.parent.mkdir(parents=True)
        companion.write_text('memory skill')
        unrelated = self.home / '.agents/skills/group/nested/SKILL.md'
        unrelated.parent.mkdir(parents=True)
        unrelated.write_text('unrelated skill')
        (self.codex / 'plugins/cache/example-market/implicit-plugin/1.0').mkdir(parents=True)
        hooks = self.codex / 'hooks.json'
        hooks.write_text(json.dumps({'hooks': {'SessionStart': [{'hooks': [
            {'type': 'command', 'command': "bash '" + str(self.codex / 'herdr-agent-state.sh') + "' session"},
            {'type': 'command', 'command': 'hindsight-session-start'},
        ]}], 'Stop': [{'hooks': [{'type': 'command', 'command': 'hindsight-stop'}]}]}}))
        with config.open('a') as stream:
            stream.write('\n[[skills.config]]\npath = ' + json.dumps(str(companion))
                         + '\nenabled = true\n')
        result = self.reconcile()
        self.assertEqual(result.returncode, 0, result.stderr)
        data = tomllib.loads(config.read_text())
        self.assertFalse(data['plugins']['local@example']['enabled'])
        self.assertFalse(data['plugins']['implicit-plugin@example-market']['enabled'])
        self.assertFalse(data['mcp_servers']['custom']['enabled'])
        self.assertTrue(data['mcp_servers']['hindsight'].get('enabled', True))
        self.assertFalse(data['features']['apps'])
        self.assertFalse(data['features']['plugins'])
        self.assertFalse(data['features']['remote_plugin'])
        self.assertFalse(data['features']['recommended_plugins'])
        self.assertFalse(data['features']['memories'])
        self.assertTrue(data['features']['multi_agent'])
        self.assertFalse(data['memories']['generate_memories'])
        self.assertFalse(data['memories']['use_memories'])
        self.assertFalse(data['skills']['bundled']['enabled'])
        rules = {r['path']: r['enabled'] for r in data['skills']['config']}
        self.assertTrue(rules[str(companion)])
        self.assertFalse(rules[str(unrelated)])
        self.assertEqual(desktop.read_text(), 'desktop sentinel')
        self.assertEqual(project.read_text(), 'project sentinel')
        commands = [h['command'] for entries in json.loads(hooks.read_text())['hooks'].values()
                    for entry in entries for h in entry['hooks']]
        self.assertEqual(commands, ['hindsight-session-start', 'hindsight-stop', '/managed/rtk hook codex'])
        first = config.read_bytes()
        self.assertEqual(self.reconcile().returncode, 0)
        self.assertEqual(config.read_bytes(), first)

    def test_preserves_runtime_state_and_comments_while_reapplying_owned_settings(self):
        config = self.codex / 'config.toml'
        config.write_text('# personal note\nmodel = "old"\n[projects."/work"]\ntrust_level = "trusted"\n'
                          '[features]\nmemories = true\n[plugins."local@example"]\nenabled = true\n'
                          '[plugins."gmail@openai-curated-remote"]\nenabled = true\n'
                          '[mcp_servers.serena]\nurl = "https://obsolete.invalid"\n')
        (self.codex / 'auth.json').write_text('untouched')
        result = self.reconcile()
        self.assertEqual(result.returncode, 0, result.stderr)
        content = config.read_text()
        data = tomllib.loads(content)
        self.assertIn('# personal note', content)
        self.assertEqual(data['model'], 'test-model')
        self.assertEqual(data['projects']['/work']['trust_level'], 'trusted')
        self.assertTrue(data['features']['memories'])
        self.assertTrue(data['features']['apps'])
        self.assertTrue(data['plugins']['local@example']['enabled'])
        self.assertTrue(data['plugins']['gmail@openai-curated-remote']['enabled'])
        self.assertNotIn('url', data['mcp_servers']['serena'])
        self.assertEqual((self.codex / 'auth.json').read_text(), 'untouched')
        self.assertEqual(config.stat().st_mode & 0o777, 0o600)
        self.assertTrue(list(self.codex.glob('config.toml.home-manager-backup.*')))

    def test_preserves_unmanaged_desktop_and_local_mcps(self):
        config = self.codex / 'config.toml'
        config.write_text('[mcp_servers.node_repl]\ncommand = "/nix/store/old-chatgpt/lib/chatgpt/resources/cua_node/bin/node_repl"\n'
                          '[mcp_servers.hindsight]\ncommand = "node"\n'
                          '[mcp_servers.custom]\ncommand = "/local/mcp"\n')
        self.assertEqual(self.reconcile().returncode, 0)
        servers = tomllib.loads(config.read_text())['mcp_servers']
        self.assertTrue(servers['node_repl'].get('enabled', True))
        self.assertEqual(servers['hindsight']['command'], 'node')
        self.assertNotIn('enabled', servers['custom'])

    def test_removes_former_managed_feature_overrides_without_changing_other_features(self):
        config = self.codex / 'config.toml'
        config.write_text('[features]\ncode_mode = true\ncode_mode_only = true\nmemories = true\n')
        result = self.reconcile()
        self.assertEqual(result.returncode, 0, result.stderr)
        features = tomllib.loads(config.read_text())['features']
        self.assertNotIn('code_mode', features)
        self.assertNotIn('code_mode_only', features)
        self.assertTrue(features['memories'])
        self.assertTrue(features['hooks'])

    def test_hooks_and_configuration_are_idempotent(self):
        hooks = self.codex / 'hooks.json'
        original = {'hooks': {'Stop': [{'hooks': [{'type': 'command', 'command': 'hindsight-stop'}]}],
                            'PreToolUse': [{'matcher': 'Bash', 'hooks': [{'type': 'command', 'command': 'user-hook'}]}]}}
        hooks.write_text(json.dumps(original))
        self.assertEqual(self.reconcile().returncode, 0)
        first = {p: p.read_bytes() for p in [hooks, self.codex / 'config.toml']}
        backups = set(self.home.rglob('*.home-manager-backup.*'))
        self.assertEqual(self.reconcile().returncode, 0)
        self.assertEqual(first, {p: p.read_bytes() for p in first})
        self.assertEqual(backups, set(self.home.rglob('*.home-manager-backup.*')))
        data = json.loads(hooks.read_text())
        self.assertEqual(data['hooks']['Stop'], original['hooks']['Stop'])
        commands = [h['command'] for entry in data['hooks']['PreToolUse'] for h in entry['hooks']]
        self.assertEqual(commands, ['user-hook', '/managed/rtk hook codex'])

    def test_malformed_input_does_not_partially_update_config(self):
        config = self.codex / 'config.toml'
        config.write_text('model = "old"\n')
        hooks = self.codex / 'hooks.json'
        hooks.write_text('{broken')
        self.assertNotEqual(self.reconcile().returncode, 0)
        self.assertEqual(config.read_text(), 'model = "old"\n')
        self.assertEqual(hooks.read_text(), '{broken')
        self.assertFalse(list(self.home.rglob('*.home-manager-backup.*')))

    def test_migrates_legacy_executable_and_preserves_serena_projects(self):
        binary = self.home / '.local/bin/codex'
        binary.parent.mkdir(parents=True)
        binary.write_text('legacy binary')
        serena = self.home / '.serena/serena_config.yml'
        serena.parent.mkdir()
        serena.write_text('projects:\n  - /work\ntrusted_project_path_patterns:\n  - /work\n')
        self.assertEqual(self.reconcile().returncode, 0)
        self.assertEqual(binary.readlink(), pathlib.Path('/managed/codex'))
        self.assertEqual(next(binary.parent.glob('codex.home-manager-backup.*')).read_text(), 'legacy binary')
        self.assertIn('/work', serena.read_text())
        self.assertIn(str(self.home / 'src') + '/**', serena.read_text())


if __name__ == '__main__':
    unittest.main()
