import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.parse import parse_qs, urlparse

SOURCE = Path(
    os.environ.get(
        "OBS_PODCAST_SOURCE",
        Path(__file__).resolve().parents[1] / "modules/home/desktop/obs-podcast.py",
    )
)
spec = importlib.util.spec_from_file_location("obs_podcast", SOURCE)
assert spec and spec.loader
podcast = importlib.util.module_from_spec(spec)
spec.loader.exec_module(podcast)


class PodcastTest(unittest.TestCase):
    def test_seed_is_private_writable_and_preserves_edits(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config, data = root / "config", root / "data"
            podcast.seed(config, data, root)
            profile = config / "obs-studio/basic/profiles/T14_Podcast/basic.ini"
            collection = config / "obs-studio/basic/scenes/T14_Podcast.json"
            state = data / "obs-podcast/room.json"
            before = state.read_bytes()
            # OBS does not accept ConfigParser's default 'Key = value' spelling.
            self.assertIn("Name=T14 Podcast\n", profile.read_text())
            self.assertIn("Mode=Advanced\n", profile.read_text())
            self.assertNotIn(" = ", profile.read_text())
            for path in (profile, collection, state, data / "obs-podcast/links.html"):
                self.assertFalse(path.is_symlink())
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(state.parent.stat().st_mode & 0o777, 0o700)
            obs = config / "obs-studio"
            self.assertEqual(obs.stat().st_mode & 0o777, 0o700)
            # Even an OBS atomic-save under umask 022 remains behind a private directory.
            replacement = collection.with_suffix(".json.tmp")
            replacement.write_text("OBS save")
            replacement.chmod(0o644)
            replacement.replace(collection)
            self.assertEqual(obs.stat().st_mode & 0o777, 0o700)
            profile.write_text("edited profile")
            collection.write_text("edited scenes")
            podcast.seed(config, data, root)
            self.assertEqual(profile.read_text(), "edited profile")
            self.assertEqual(collection.read_text(), "edited scenes")
            self.assertEqual(state.read_bytes(), before)
            self.assertTrue((root / "Videos/Podcasts").is_dir())

    def test_profile_has_full_mix_plus_isolated_tracks(self):
        profile = podcast.profile(Path("recordings"))
        self.assertEqual(profile["Output"]["Mode"], "Advanced")
        self.assertEqual(profile["AdvOut"]["RecTracks"], "31")
        self.assertEqual(profile["AdvOut"]["RecFormat2"], "mkv")
        self.assertEqual(profile["Video"]["OutputCY"], "1080")
        self.assertEqual(profile["Audio"]["SampleRate"], "48000")

    def test_shared_sources_and_track_masks(self):
        collection = podcast.collection(podcast.new_secrets())
        sources = {source["name"]: source for source in collection["sources"]}
        self.assertEqual(len(sources), len(collection["sources"]))
        self.assertEqual(sources["Host - Blue USB mic"]["mixers"], 3)
        self.assertEqual(sources["Program - selected computer audio"]["mixers"], 9)
        for n, mask in ((1, 5), (2, 17)):
            source = sources[f"Guest {n} - VDO"]
            self.assertEqual(source["mixers"], mask)
            self.assertTrue(source["settings"]["reroute_audio"])
            self.assertFalse(source["settings"]["shutdown"])
            self.assertEqual(source["monitoring_type"], 0)
        for scene in (source for source in sources.values() if source["id"] == "scene"):
            names = [item["name"] for item in scene["settings"]["items"]]
            for name in names:
                self.assertIn(name, sources)
            if scene["name"] != podcast.AUDIO:
                self.assertIn(podcast.AUDIO, names)
            else:
                for item in scene["settings"]["items"]:
                    if item["name"].startswith("Guest"):
                        self.assertLess(item["pos"]["x"], -1920)
        self.assertIsNone(collection["DesktopAudioDevice1"])
        self.assertIsNone(collection["AuxAudioDevice1"])

    def test_links_match_guest_slots_and_request_local_backup(self):
        state = podcast.new_secrets()
        self.assertEqual(len(set(state.values())), 4)
        links = podcast.links(state)
        for n in (1, 2):
            invite = parse_qs(
                urlparse(links[f"Guest {n} — send this invitation"]).query
            )
            view = parse_qs(urlparse(links[f"OBS guest {n} — private"]).query)
            self.assertEqual(invite["push"], view["view"])
            self.assertEqual(invite["record"], ["6000"])
            self.assertEqual(invite["splitrecording"], ["5"])
            self.assertEqual(invite["password"], view["password"])
            self.assertEqual(invite["room"], view["room"])

    def test_audio_start_rolls_back_partial_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "audio.json"
            with (
                patch.object(
                    podcast,
                    "pactl",
                    side_effect=["headphones", "42", RuntimeError("loopback failed")],
                ),
                patch.object(podcast.subprocess, "run") as run,
            ):
                with self.assertRaisesRegex(RuntimeError, "loopback failed"):
                    podcast.audio_start(path)
                run.assert_called_once_with(
                    ["pactl", "unload-module", "42"], check=False
                )
            self.assertFalse(path.exists())

    def test_audio_stop_does_not_unload_recycled_ids(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "audio.json"
            path.write_text(json.dumps([41, 42]))
            modules = [
                {
                    "index": 41,
                    "name": "module-null-sink",
                    "argument": "sink_name=other",
                },
                {
                    "index": 42,
                    "name": "module-loopback",
                    "argument": "source=podcast_program.monitor sink=headphones",
                },
            ]
            with (
                patch.object(podcast, "pactl", return_value=json.dumps(modules)),
                patch.object(podcast.subprocess, "run") as run,
            ):
                podcast.audio_stop(path)
                run.assert_called_once_with(
                    ["pactl", "unload-module", "42"], check=True
                )
            self.assertFalse(path.exists())

    def test_audio_recovers_stale_state_after_server_loss(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "audio.json"
            path.write_text("[41, 42]")
            with (
                patch.object(
                    podcast,
                    "pactl",
                    side_effect=subprocess.CalledProcessError(1, "pactl"),
                ),
                self.assertRaises(subprocess.CalledProcessError),
            ):
                podcast.audio_stop(path)
            self.assertTrue(path.exists())
            with patch.object(
                podcast, "pactl", side_effect=["[]", "headphones", "43", "44"]
            ):
                podcast.audio_start(path)
            self.assertEqual(json.loads(path.read_text()), [43, 44])

    def test_audio_start_success_does_not_change_system_defaults(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "audio.json"
            with patch.object(
                podcast, "pactl", side_effect=["headphones", "41", "42"]
            ) as pactl:
                podcast.audio_start(path)
                commands = [call.args for call in pactl.call_args_list]
                self.assertEqual(commands[0], ("get-default-sink",))
                self.assertIn("source=podcast_program.monitor", commands[2])
                self.assertIn("sink=headphones", commands[2])
                self.assertFalse(
                    any("set-default-sink" in command for command in commands)
                )
            self.assertEqual(json.loads(path.read_text()), [41, 42])


if __name__ == "__main__":
    unittest.main()
