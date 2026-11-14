# T14 OBS podcast studio

## Start here

Home Manager installs **OBS Podcast Studio** in the application launcher on T14.
Run `obs-podcast` from a terminal for the same setup. This creates the writable
**T14 Podcast** profile/scene collection on first launch, starts its programme
audio bus, and opens OBS. It does **not** start recording or streaming.

- **Video:** 1920×1080, 30 fps, H.264/x264 CRF 20, veryfast preset. This is a
  conservative software baseline, not an untested hardware encoder preset.
- **Audio:** 48 kHz stereo, AAC 320 kbps per track.
- **Files:** `~/Videos/Podcasts/`, MKV. Use **File → Remux Recordings** for MP4
  delivery after recording; keep the MKV master. MKV tolerates interrupted
  recording better than ordinary MP4, but is not a backup strategy.
- **Hardware:** OBSBOT Tiny 2 Lite camera, Blue USB microphone. Stable device
  identities are used instead of changing `/dev/videoN` numbers. Re-select a
  device in source Properties if you replace/disconnect that hardware.

## One-time device and screen selection

1. Connect the OBSBOT and Blue mic; choose your **headphones** as the desktop
   output **before launching**. Speakers produce acoustic echo.
2. Open **OBS Podcast Studio**. Decline the automatic streaming setup wizard if
   offered; do not let it replace the recording profile.
3. Check **Host - OBSBOT** Properties/preview. Adjust framing with Tiny4Linux or
   Camset. To add another camera, add a **Video Capture Device (V4L2)** source
   to the desired scene; choose its video device, not another microphone.
4. Open **Screen - choose in Properties**, press the screen/window selection
   button, and authorize the desired screen/window in the Wayland portal.
   A portal dialog can appear at first launch. This cannot be pre-authorized
   by a declarative config. Select the intended display, not OBS itself.
5. Speak normally: the **Host - Blue USB mic** meter should move, ideally with
   speech peaks around −12 to −6 dB, never red. Adjust mic gain/position rather
   than adding aggressive gates/compression before a listening test. If the
   Blue mic presents mono audio on only one channel, enable **Mono** for it in
   Advanced Audio Properties. Keep OBSBOT/Studio Display mic audio disabled.
6. If the OBSBOT preview is black/frozen, check that the camera is awake, close
   other camera applications, and reconnect it directly to a laptop USB port
   with a known-good cable. A detected device or selected format does not prove
   it is delivering frames. Re-open its source Properties after reconnecting;
   try 1280×720 at 30 fps to help distinguish a transport/bandwidth problem.
7. Make a short rehearsal, then play it back with headphones. Check lip sync
   and adjust per-source sync offset only if needed. Check **View → Stats** for
   rendering/encoding lag; close heavy apps or lower output to 1280×720 if needed.

### Black screen / missing screen-share chooser

If the camera inset works but the screen is black, open the screen source's
**Properties** and retry **Select Screen/Window**. A log error such as
`Error creating screencast session: Timeout was reached` can indicate a stuck
portal backend, not a scene-layout problem. During setup, the Hyprland portal
was running but stopped answering its D-Bus screencast interface. Restarting the
portal services restored responsiveness, and the user confirmed screen capture
worked after retrying the selector:

```sh
fix-screenshare
```

This Home Manager-installed command is on your PATH; `fix-screenshare --help`
explains its effects without restarting anything. It runs
`systemctl --user restart xdg-desktop-portal-hyprland.service xdg-desktop-portal.service`.

This interrupts existing screen shares. It does not restart the camera or
PipeWire audio. Afterward, retry the OBS selector or start a fresh browser share.
Riverside/Descript browser screen sharing uses the same Wayland portal path, so
this failure can affect those too; their recovery must be checked separately.
Do not restart the portals automatically on every OBS launch.

### OBSBOT validation caveat

During initial setup, this OBSBOT emitted malformed MJPEG startup buffers. OBS
32.1.2's V4L2 source stopped after two frames at both 1080p30 and 720p30, while
FFmpeg discarded bad buffers and continued near 30 fps (frames discarded to
`/dev/null`, not saved). On the final retry, OBS was reopened with the tracking
helper temporarily paused, then that helper was restored. The user confirmed a
**live, moving 1080p preview**. This single recovery does not establish that the
tracking helper caused the startup problem or that it cannot recur; no permanent
tracking-service change was made.

If it recurs, close/reopen the camera source/OBS first. A controlled launch with
`obsbot-tracking-resume.service` temporarily stopped and subsequently restarted
reproduces the successful trial; always restore that service afterward. If the
problem persists, check the cable/reconnect and investigate the OBS/UVC decode
path rather than assuming lower resolution or audio changes will fix it. No USB
reset, firmware or power-policy change was made. Rehearse before a show.

## Scene buttons

| Scene | Picture |
| --- | --- |
| 01 - Solo | Host camera |
| 02 - Screen + host | Selected screen/window and host corner inset |
| 03 - Interview | Host and guest 1 side-by-side |
| 04 - Panel | Host, guest 1, guest 2/cohost |
| 05 - Screen + panel | Selected screen/window with participant insets |

**00 - Audio (keep in every scene)** is a utility scene, not a show layout. It
keeps the host mic, programme bus and both guest sources active, with guest
pictures off-canvas. Guest audio continues when you switch to solo or screen.
The picture layouts reuse the **same** guest source objects, not new browser
connections. Do not hide/remove the utility scene or add duplicate guest audio
captures. To use more than two remote participants, add another browser source,
reuse it in the utility/layout scenes, and assign its full-mix/isolated track.
There are six OBS audio tracks; track 6 is spare.

## Computer audio without doubled guests

The opt-in `podcast-audio.service` creates **Podcast-Program** and loops its
playback to the physical output selected when the service starts. It never
changes the desktop's default sink or loops your microphone back to itself.

1. Start the application that will play a clip/music/demo.
2. Open `pavucontrol` → **Playback**. Route **only that application's playback**
   to **Podcast-Program**. It is now audible in your headphones and recorded by
   **Program - selected computer audio**.
3. Leave the VDO.Ninja director browser on the **real headphones**, not
   Podcast-Program. Keep browser-source monitoring **Off** in OBS. You hear
   guests once through the director browser; OBS records them once through its
   individual guest sources. A dedicated browser/profile for clips helps keep
   director and clip playback separate; some browsers group tabs as one stream.

Do not enable global Desktop Audio, capture your whole headphone output, or
route the director browser into this bus: all would duplicate guest audio.
The deliberately selected-app approach also avoids recording notification sounds.

The programme bus records clips **for the episode**; it does **not** send them
back to guests. Let guests watch/listen to shared material through your call's
screen-share feature if supported. Sending an OBS mix back requires a separate
**mix-minus** (host + clips, excluding the guests' own return) and is not enabled.
This setup does not install a kernel virtual-camera driver or promise that the
OBS programme can be selected as a webcam in a call.

The audio bus stays available after OBS closes so application routing does not
vanish mid-session. To remove it, run:

```sh
systemctl --user stop podcast-audio.service
```

After changing headphones/output devices, close OBS and restart that service
before reopening. Check/re-route clip applications in pavucontrol after stopping
the bus or restarting PipeWire. It is not enabled at login.

## Guests/cohosts: recommended VDO.Ninja workflow

Open your private links page:

```sh
obs-podcast-setup links
```

It lives at `~/.local/share/obs-podcast/links.html`; room/password/stream IDs are
randomly generated **locally at runtime**, not committed or embedded in the Nix
store. Do not share the whole page, director URL, OBS URLs, exported scene JSON,
or `room.json`. Send only the corresponding **Guest 1** or **Guest 2** invitation.
These are persistent reusable links: invite only trusted participants. Anyone
with a guest invitation has room access. For new secrets, close OBS and back up
**both** the room directory and the T14 scene JSON, then launch again to regenerate
both together. Never regenerate only the room file: existing OBS URLs would no
longer match. Backups still contain secrets; keep them private.

1. You open the **Director** link in a browser. Join the room's audio using the
   **physical Blue mic** and real headphones. Turn your director camera off to
   avoid competing with OBS for the OBSBOT. The director interface's mic/join
   controls must be enabled: guests cannot hear a silent director. If they need
   to see you too, choose a different physical camera (e.g. integrated camera)
   for the director browser. Do not use a monitor/loopback as its microphone.
2. Guests open their invitation in Chrome/Edge on a computer, allow camera/mic,
   choose their best camera and headset/USB microphone, and join. No OBS or
   account installation is required. Ask everyone to wear headphones, use good
   lighting and a quiet room; wired Ethernet helps. Browser permissions and
   firewalls still need a real call test.
3. Their individual feeds should populate **Guest 1 - VDO** and **Guest 2 - VDO**
   in OBS. **Control audio via OBS** is already enabled on these Browser Sources;
   monitoring is off. Refresh a source if its connection stalls. Do not mute
   the OBS guest source as a way to mute director playback; that mutes recording.
4. Check the guest's local recording controls/indicator. Invitations request
   `record=6000&splitrecording=5`: approximately 6 Mbps local video and five-minute
   saves. This is a request, **not proof that recording started or saved**.
   Confirm with a short test; allow download/file-save prompts. The director's
   advanced recording controls can start recording at the guest end if needed.
5. Clap once on camera after all recordings start. Record the composed programme
   in OBS. At the end, stop both OBS and guest-local recording, wait for downloads
   to finish, and ask each guest to send **all** saved files via your preferred
   file-transfer service. There is **no automatic upload/recovery** configured.
   Do not close their tabs until files are saved and checked. Splitting can have
   brief gaps and is not a frame-perfect continuous master.

### Quality trade-off

OBS records the **received live feed**, so resolution/bitrate depend on camera,
CPU, upload bandwidth and network conditions. Requested 1080p/6 Mbps is not a
guarantee. VDO.Ninja provides individual WebRTC feeds without needing OBS at the
guest end, but does not eliminate network compression or dropped frames.

For the best edit, use the guest's **local original audio/video**, not just the
network feed. A local recording avoids damage from the Internet leg; collect it
and sync it in the editor. OBS's isolated audio tracks help repair the live mix
but do not produce separate camera video masters. A paid local-recording service
can simplify uploads/recovery if VDO's manual file collection becomes tedious.
Riverside/Descript browser screen-sharing failing on Linux does not prevent OBS
from capturing the screen directly, or imply all their guest-local recording
features fail. VDO.Ninja plus OBS avoids depending on their Linux screen-sharing
for the recorded programme.

## Recording tracks

| Track | Contents |
| --- | --- |
| 1 | Complete listening mix: host + both guests + selected computer audio |
| 2 | Blue host microphone only |
| 3 | Guest 1 only |
| 4 | Selected computer audio only |
| 5 | Guest 2/cohost only |
| 6 | Spare; not selected for recording initially |

Most ordinary players play **one** track, so track 1 is the ready-to-listen mix.
In an editor use either track 1 **or** the isolated tracks, not both together.
OBS makes one composed video, not a separate video file per source.

## Zoom / Google Meet fallback

Yes: guests can simply join a regular Zoom/Meet call. In a duplicate scene
collection, remove/disable the VDO guest sources, capture the pinned participant
window with **Screen Capture (PipeWire)**, and route the call application's
playback to **Podcast-Program**. The Blue mic remains a separate OBS source;
the call must use that **physical mic**, never the programme bus/desktop monitor.
Keep OBS monitoring off. Headphones are still required.

Zoom/Meet video layout, overlays, bandwidth adaptation and conferencing audio
processing are then baked into the captured result. Multiple received voices
usually arrive as one mixed call stream, not isolated OBS sources. A browser
profile dedicated to Meet avoids mixing unrelated tabs. Zoom's local recording
has an option to record separate audio files per participant; verify that option
in the installed client. Meet's built-in recording depends on Workspace account
eligibility/admin policy. Neither turns ordinary call capture into guest-local
original camera recordings. For the highest quality, still ask guests for a
local recording, or use a purpose-built local-recording service.

## Persistence and verification

Home Manager manages the launcher/helper/service, **not symlinks to live OBS
JSON**. First launch seeds missing files only; subsequent launches preserve edits
and other profiles. OBS settings/backups are protected by a private config
directory. Do not use an OBS export as a public preset: it contains private URLs.
To reset the baseline, close OBS, back up the T14 profile directory and
`~/.config/obs-studio/basic/scenes/T14_Podcast.json`, then launch again. Retaining
`room.json` retains the same invitation links.

Hardware-free regression check:

```sh
nix build .#checks.x86_64-linux.obs-podcast
```

It checks private/idempotent seeding, OBS-compatible INI spelling, source
references, persistent shared guest audio, track masks, invitation matching and
programme-bus cleanup/recovery. During setup, an additional synthetic OBS 32.1.2
recording was verified as 1080p30 H.264/MKV with all five named 48 kHz AAC tracks,
steady isolated/mixed audio levels across scene changes, and no reported dropped
render/encode frames in that short test. Synthetic sources do not exercise the
real camera, microphone acoustics or a remote guest.

These checks do not prove portal permission, camera framing, echo-free acoustics, guest
connectivity, lip sync, or guest download success. Rehearse those before a show.

Sources:

- [OBS multi-track audio](https://obsproject.com/kb/multiple-audio-track-recording-guide)
- [OBS recording formats](https://obsproject.com/kb/standard-recording-output-guide)
- [VDO.Ninja call-in show with OBS](https://docs.vdo.ninja/guides/call-in-show-with-obs)
- [VDO.Ninja consistent recording](https://docs.vdo.ninja/guides/recording-video-with-consistent-results)
- [VDO.Ninja local recording](https://docs.vdo.ninja/advanced-settings/recording-parameters/and-record)
- [VDO.Ninja recording splits](https://docs.vdo.ninja/advanced-settings/recording-parameters/and-splitrecording)
- [Zoom separate local audio files](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0076922)
- [Meet recording eligibility](https://support.google.com/meet/answer/9308681?hl=en)
