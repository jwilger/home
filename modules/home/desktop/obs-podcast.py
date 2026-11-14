"""Seed a writable OBS podcast studio and manage its opt-in programme audio bus."""

import argparse
import configparser
import html
import io
import json
import os
import secrets
import subprocess
import uuid
from pathlib import Path
from urllib.parse import urlencode

NAME = "T14 Podcast"
MIC = "alsa_input.usb-Generic_Blue_Microphones_LT_2612SQE02FZ862900046_111000-00.analog-stereo"
CAMERA = "/dev/v4l/by-id/usb-Remo_Tech_Co.__Ltd._OBSBOT_Tiny_2_Lite-video-index0"
BUS = "podcast_program"
AUDIO = "00 - Audio (keep in every scene)"


def write_new(path, content):
    """Never replace user edits; private links must not be world-readable."""
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        return
    with os.fdopen(fd, "w") as stream:
        stream.write(content)


def new_secrets():
    return {
        key: secrets.token_hex(16) for key in ("room", "password", "guest1", "guest2")
    }


def links(state):
    def url(**params):
        return "https://vdo.ninja/?" + urlencode(params)

    shared = {"room": state["room"], "password": state["password"]}
    result = {
        "Director — private, do not share": url(
            director=state["room"], password=state["password"]
        )
    }
    for number in (1, 2):
        stream = state[f"guest{number}"]
        result[f"Guest {number} — send this invitation"] = url(
            **shared,
            push=stream,
            label=f"Guest {number}",
            width=1920,
            height=1080,
            framerate=30,
            record=6000,
            splitrecording=5,
        )
        result[f"OBS guest {number} — private"] = url(
            **shared,
            view=stream,
            solo=1,
            bitrate=6000,
        )
    return result


def source(name, kind, settings, mixers=0, **extra):
    return {
        "name": name,
        "uuid": str(uuid.uuid4()),
        "id": kind,
        "versioned_id": kind,
        "settings": settings,
        "mixers": mixers,
        "volume": 1.0,
        "balance": 0.5,
        "enabled": True,
        "muted": False,
        "monitoring_type": 0,
        "sync": 0,
        "flags": 0,
        "hotkeys": {},
        "private_settings": {},
        **extra,
    }


def item(name, x=0, y=0, width=1920, height=1080):
    # OBS accepts legacy absolute coordinates and migrates them on save.
    return {
        "name": name,
        "visible": True,
        "locked": True,
        "rot": 0.0,
        "pos": {"x": x, "y": y},
        "scale": {"x": 1.0, "y": 1.0},
        "align": 5,
        "bounds_type": 2,
        "bounds_align": 0,
        "bounds": {"x": width, "y": height},
    }


def scene(name, items):
    return source(
        name,
        "scene",
        {
            "items": [dict(entry, id=i + 1) for i, entry in enumerate(items)],
            "id_counter": len(items),
            "custom_size": False,
        },
    )


def collection(state):
    urls = links(state)
    sources = [
        source("Host - Blue USB mic", "pulse_input_capture", {"device_id": MIC}, 3),
        source(
            "Program - selected computer audio",
            "pulse_output_capture",
            {"device_id": BUS + ".monitor"},
            9,
        ),
        source(
            "Host - OBSBOT",
            "v4l2_input",
            {
                "device_id": CAMERA,
                "pixelformat": int.from_bytes(b"MJPG", "little"),
                "resolution": (1920 << 32) | 1080,
                "framerate": (1 << 32) | 30,
                "buffering": False,
            },
        ),
        source(
            "Screen - choose in Properties",
            "pipewire-screen-capture-source",
            {"ShowCursor": True},
        ),
    ]
    for n, mask in ((1, 5), (2, 17)):
        sources.append(
            source(
                f"Guest {n} - VDO",
                "browser_source",
                {
                    "url": urls[f"OBS guest {n} — private"],
                    "width": 1920,
                    "height": 1080,
                    "fps": 30,
                    "fps_custom": True,
                    "reroute_audio": True,
                    "shutdown": False,
                    "restart_when_active": False,
                },
                mask,
            )
        )
    # Keep the SAME guest source objects active, off-canvas, in every scene.
    # Reusing these objects for pictures does not open a second guest connection.
    audio = scene(
        AUDIO,
        [
            item("Host - Blue USB mic"),
            item("Program - selected computer audio"),
            item("Guest 1 - VDO", -4000),
            item("Guest 2 - VDO", -4000),
        ],
    )
    layouts = [
        ("01 - Solo", [item("Host - OBSBOT")]),
        (
            "02 - Screen + host",
            [
                item("Screen - choose in Properties"),
                item("Host - OBSBOT", 1440, 810, 480, 270),
            ],
        ),
        (
            "03 - Interview",
            [
                item("Host - OBSBOT", 0, 270, 960, 540),
                item("Guest 1 - VDO", 960, 270, 960, 540),
            ],
        ),
        (
            "04 - Panel",
            [
                item("Host - OBSBOT", 0, 360, 640, 360),
                item("Guest 1 - VDO", 640, 360, 640, 360),
                item("Guest 2 - VDO", 1280, 360, 640, 360),
            ],
        ),
        (
            "05 - Screen + panel",
            [
                item("Screen - choose in Properties"),
                item("Host - OBSBOT", 0, 810, 480, 270),
                item("Guest 1 - VDO", 720, 810, 480, 270),
                item("Guest 2 - VDO", 1440, 810, 480, 270),
            ],
        ),
    ]
    sources.append(audio)
    sources.extend(scene(name, [item(AUDIO), *pictures]) for name, pictures in layouts)
    return {
        "name": NAME,
        "version": 2,
        "sources": sources,
        "groups": [],
        "scene_order": [{"name": name} for name, _ in layouts] + [{"name": AUDIO}],
        "current_scene": layouts[0][0],
        "current_program_scene": layouts[0][0],
        "current_transition": "Fade",
        "transition_duration": 200,
        "transitions": [],
        "quick_transitions": [],
        "canvases": [],
        # Explicitly disable global captures: audio comes only from named sources.
        **dict.fromkeys(
            (
                "DesktopAudioDevice1",
                "DesktopAudioDevice2",
                "AuxAudioDevice1",
                "AuxAudioDevice2",
                "AuxAudioDevice3",
                "AuxAudioDevice4",
            )
        ),
    }


class CaseSensitiveConfig(configparser.ConfigParser):
    def optionxform(self, optionstr):
        return optionstr


def profile(recordings):
    config = CaseSensitiveConfig(interpolation=None)
    config["General"] = {"Name": NAME}
    config["Output"] = {
        "Mode": "Advanced",
        "FilenameFormatting": "%CCYY-%MM-%DD %hh-%mm-%ss",
    }
    config["AdvOut"] = {
        "RecType": "Standard",
        "RecFilePath": str(recordings),
        "RecFormat2": "mkv",
        "RecEncoder": "obs_x264",
        "RecAudioEncoder": "ffmpeg_aac",
        "RecTracks": "31",
        "RecUseRescale": "false",
    }
    for n, label in enumerate(
        ("Full mix", "Host mic", "Guest 1", "Computer audio", "Guest 2"), 1
    ):
        config["AdvOut"][f"Track{n}Name"] = label
        config["AdvOut"][f"Track{n}Bitrate"] = "320"
    config["Video"] = {
        "BaseCX": "1920",
        "BaseCY": "1080",
        "OutputCX": "1920",
        "OutputCY": "1080",
        "FPSType": "0",
        "FPSCommon": "30",
        "ColorFormat": "NV12",
        "ColorSpace": "709",
        "ColorRange": "Partial",
    }
    config["Audio"] = {"SampleRate": "48000", "ChannelSetup": "Stereo"}
    return config


def parse_json(text):
    try:
        return json.loads(text)
    except json.JSONDecodeError as error:
        raise RuntimeError(
            "Invalid podcast state JSON; restore its backup before continuing"
        ) from error


def seed(config_home, data_home, home):
    private = data_home / "obs-podcast"
    private.mkdir(parents=True, exist_ok=True, mode=0o700)
    state_path = private / "room.json"
    write_new(state_path, json.dumps(new_secrets(), indent=2) + "\n")
    state = parse_json(state_path.read_text())
    obs = config_home / "obs-studio"
    obs.mkdir(parents=True, exist_ok=True, mode=0o700)
    # OBS replaces scene JSON atomically and may reset its mode on later saves.
    # Protect its whole directory, including backups, even via the normal launcher.
    obs.chmod(0o700)
    recordings = home / "Videos" / "Podcasts"
    recordings.mkdir(parents=True, exist_ok=True)
    stream = io.StringIO()
    # OBS's INI parser treats whitespace before '=' as part of the key.
    profile(recordings).write(stream, space_around_delimiters=False)
    target = obs / "basic" / "profiles" / "T14_Podcast"
    write_new(target / "basic.ini", stream.getvalue())
    write_new(
        target / "recordEncoder.json",
        json.dumps(
            {
                "rate_control": "CRF",
                "crf": 20,
                "preset": "veryfast",
                "profile": "high",
                "keyint_sec": 2,
            }
        ),
    )
    write_new(
        obs / "basic" / "scenes" / "T14_Podcast.json",
        json.dumps(collection(state), indent=2) + "\n",
    )
    entries = "\n".join(
        f'<li><a href="{html.escape(url, quote=True)}">{html.escape(label)}</a></li>'
        for label, url in links(state).items()
    )
    write_new(
        private / "links.html",
        '<!doctype html><meta charset="utf-8"><title>Podcast links</title>'
        "<h1>Private podcast links</h1><p>Only share the guest invitation, not this page or director link.</p>"
        f"<ul>{entries}</ul><p>Use headphones. Guests: allow camera/mic, save local recordings before closing.</p>",
    )
    return private / "links.html"


def pactl(*args):
    return subprocess.check_output(["pactl", *args], text=True).strip()


def audio_start(state_path):
    # A service owns the module IDs; never unload unrelated user modules.
    if state_path.exists():
        # Recover module IDs left behind after an audio-server/service failure.
        audio_stop(state_path)
    sink = pactl("get-default-sink")
    if sink == BUS:
        raise RuntimeError(
            "Choose your headphones as default output before starting podcast audio"
        )
    modules = []
    try:
        modules.append(
            int(
                pactl(
                    "load-module",
                    "module-null-sink",
                    f"sink_name={BUS}",
                    "sink_properties=device.description=Podcast-Program",
                    "rate=48000",
                    "channels=2",
                )
            )
        )
        modules.append(
            int(
                pactl(
                    "load-module",
                    "module-loopback",
                    f"source={BUS}.monitor",
                    f"sink={sink}",
                    "latency_msec=30",
                )
            )
        )
        write_new(state_path, json.dumps(modules))
    except Exception:
        for module in reversed(modules):
            subprocess.run(["pactl", "unload-module", str(module)], check=False)
        raise


def audio_stop(state_path):
    if not state_path.exists():
        return
    # Check ownership after PipeWire restarts; numeric IDs may have been recycled.
    current = {
        module["index"]: module
        for module in parse_json(pactl("-f", "json", "list", "modules"))
    }
    for module in reversed(parse_json(state_path.read_text())):
        entry = current.get(module)
        if (
            entry
            and BUS in entry.get("argument", "")
            and entry["name"] in ("module-loopback", "module-null-sink")
        ):
            subprocess.run(["pactl", "unload-module", str(module)], check=True)
    state_path.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "command", choices=("seed", "links", "audio-start", "audio-stop")
    )
    args = parser.parse_args()
    home = Path.home()
    if args.command.startswith("audio-"):
        state_path = Path(os.environ["XDG_RUNTIME_DIR"]) / "obs-podcast-audio.json"
        (audio_start if args.command == "audio-start" else audio_stop)(state_path)
    else:
        path = seed(
            Path(os.environ.get("XDG_CONFIG_HOME", home / ".config")),
            Path(os.environ.get("XDG_DATA_HOME", home / ".local/share")),
            home,
        )
        if args.command == "links":
            subprocess.run(["xdg-open", str(path)], check=True)


if __name__ == "__main__":
    main()
