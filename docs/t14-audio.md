# T14 desk and meeting audio

| Use | Microphone | Playback |
| --- | --- | --- |
| Desk meeting in Chrome | Blue Yeti (Blue Microphones Analog Stereo) | Studio Display Analog Stereo |
| Laptop by itself | Ryzen HD Audio Controller **Digital Microphone** | Laptop speakers |
| OBS recording | Explicit **Host - Blue USB mic** source | Headphones plugged into the Yeti |

Home Manager installs a WirePlumber 0.5 fragment **only on `jwilger-t14`**. With
no saved choices, it prefers the Yeti's **Analog Stereo Duplex** profile so both
its mic and headphone jack exist. It ranks the Yeti mic above the laptop digital
mic, the digital mic above the display mic, and the Studio Display speakers above
the Yeti output. It doesn't change volume, unmute devices, or move explicitly
routed apps. Changes take effect on the next WirePlumber start after Home Manager
activation. Between calls or recordings, run `systemctl --user restart wireplumber.service`
and verify the priorities below. A graphical logout alone may leave the daemon running.

## Check the route

1. Use `wpctl status -n` to see the default (`*`) source and sink. For a policy
   check, `wpctl inspect ID` should show `priority.session` **2400** on the Yeti
   mic, **2300** on the laptop digital mic, and **1250** on the display output.
   IDs can change after every reconnect. A correct default alone doesn't prove
   the fragment loaded: WirePlumber also remembers manual choices.
2. Saved choices (including earlier Bluetooth choices) take precedence. Use
   `wpctl set-default ID` to change **just** the mic or speaker. To deliberately
   return to automatic selection, `wpctl clear-default 1` forgets saved mic
   choices; `wpctl clear-default 0` forgets saved output choices. Neither resets
   the card profile. If a previously saved Yeti profile hides the headphone
   output, select **Analog Stereo Duplex** in `pavucontrol` → **Configuration**
   between calls. Leave the fallback mic unmuted if you want to use it.
3. In Chrome, allow mic access for the Zoom site and check
   `chrome://settings/content/microphone`. Use the system default in Chrome and
   “same as system” in Zoom if offered. During Zoom's mic test, check the Chrome
   stream on `pavucontrol` → **Recording**: it should use the physical mic, not
   the display mic or a speaker monitor. Test **Playback** separately.
4. For recording, select the Yeti as **output before** starting `obs-podcast`.
   Route only the programme application's playback to **Podcast-Program**;
   keep the physical mic separate and monitoring off. The programme monitor
   does not exist until `podcast-audio.service` starts. If already active on the
   wrong output, close OBS, select headphones, run
   `systemctl --user restart podcast-audio.service`, then relaunch. Select the
   Studio Display again after recording. See [the OBS runbook](obs-podcast.md)
   for guest routing, screen capture and recording tracks.

## Rehearse before a meeting or recording

- Run a Chrome Zoom test call longer than the usual time to failure. Have the
  far end confirm speech after mute/unmute and an idle interval. Between calls,
  unplug the Yeti and check `wpctl inspect @DEFAULT_AUDIO_SOURCE@` for the laptop
  digital mic. Reconnect and test again. An already-open Chrome track may need
  to be reselected or reopened. The mic LED isn't a signal meter.
- Record a short MKV with speech, a screen capture and a clip. Aim for speech
  peaks around −12 to −6 dBFS without clipping. Listen to track 1 for a single
  copy of both sounds, track 2 for just the host and track 4 for just the clip.
  Five streams in the file doesn't prove the signals reached them. A fresh
  **T14 Podcast** profile is seeded with Advanced recording and tracks 1–5;
  if an existing profile is mix-only, inspect **Settings → Output** rather than
  replacing personal scenes or guest URLs.

## If Zoom says there is no mic

**Before unplugging anything**, note the time, check the Yeti's input meter in
`pavucontrol`, and capture the following while Zoom is trying to record:

```sh
date -Is
grep -i 'Blue Microphones' /proc/asound/cards
wpctl status -n
pactl get-default-source
pactl list short sources   # map Pulse source indices to names
pactl list source-outputs  # which source index each recording client is using
journalctl -k -b --since '5 minutes ago' -g 'USB disconnect|Blue Microphones|cannot submit urb'
journalctl --user -b --since '5 minutes ago' -u wireplumber -u pipewire -u pipewire-pulse
```

- **Gone from ALSA, kernel disconnect before intervention:** try a known-good USB
  data cable on the same direct port, then try another port.
- **Present in ALSA, missing in WirePlumber:** check the Yeti card profile and
  user journal. An idle PipeWire node marked `SUSPENDED` is not a USB disconnect.
- **Present in both, input meter moves:** check Chrome's recording stream,
  reselect the mic or rejoin computer audio in Zoom before restarting anything.
  Open `chrome://webrtc-internals` before a rehearsal for capture diagnostics;
  its dumps can contain private call and network details.

The observed replug happened *after* Zoom reported failure. The Yeti already had
USB runtime power control set to `on`; PipeWire and OBS were both at 48 kHz. No
USB, power-management or sample-rate change is part of this policy.
