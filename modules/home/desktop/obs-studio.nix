{
  config,
  lib,
  pkgs,
  ...
}:
let
  isT14 = config.jwilger.hostProfile == "jwilger-t14";
  helper = pkgs.writeShellApplication {
    name = "obs-podcast-setup";
    runtimeInputs = [
      pkgs.pulseaudio
      pkgs.xdg-utils
    ];
    text = ''
      exec ${pkgs.python3}/bin/python3 ${./obs-podcast.py} "$@"
    '';
  };
  screenShareRecovery = pkgs.writeShellApplication {
    name = "fix-screenshare";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      if [[ $# -eq 1 && ( "$1" == --help || "$1" == -h ) ]]; then
        echo "Usage: fix-screenshare"
        echo "Restart the screen-sharing portals, interrupting existing screen shares."
        echo "Camera and PipeWire audio are not restarted. Retry screen selection afterward."
        exit 0
      fi
      if [[ $# -ne 0 ]]; then
        echo "Usage: fix-screenshare" >&2
        exit 2
      fi
      echo "Restarting screen-sharing portals; existing screen shares will disconnect."
      systemctl --user restart xdg-desktop-portal-hyprland.service xdg-desktop-portal.service
      echo "Portals restarted. Retry screen/window selection in OBS or your browser."
    '';
  };
  launcher = pkgs.writeShellApplication {
    name = "obs-podcast";
    runtimeInputs = [
      helper
      pkgs.systemd
      pkgs.procps
      pkgs.util-linux
      pkgs.coreutils
    ];
    text = ''
      umask 077
      exec 9>"$XDG_RUNTIME_DIR/obs-podcast.lock"
      flock -n 9 || { echo "Podcast studio is already opening/running." >&2; exit 1; }
      if pgrep -u "$(id -u)" -x 'obs|\.obs-wrapped' >/dev/null; then
        echo "OBS is already running. Close it before opening the podcast studio." >&2
        exit 1
      fi
      obs-podcast-setup seed
      systemctl --user start podcast-audio.service
      exec ${config.programs.obs-studio.finalPackage}/bin/obs \
        --profile 'T14 Podcast' --collection 'T14 Podcast' "$@"
    '';
  };
in
lib.mkIf
  (builtins.elem config.jwilger.hostProfile [
    "gregor"
    "jwilger-t14"
  ])
  {
    programs.obs-studio = {
      enable = true;
      plugins = with pkgs.obs-studio-plugins; [
        wlrobs
        input-overlay
        obs-pipewire-audio-capture
      ];
    };

    home.packages = lib.mkIf isT14 [
      launcher
      helper
      screenShareRecovery
      pkgs.pavucontrol
    ];

    # Seed only on launch, not every activation; OBS owns its writable settings.
    xdg.desktopEntries.obs-podcast = lib.mkIf isT14 {
      name = "OBS Podcast Studio";
      genericName = "Video podcast recording";
      exec = "${launcher}/bin/obs-podcast";
      icon = "com.obsproject.Studio";
      terminal = false;
      categories = [
        "AudioVideo"
        "Recorder"
      ];
    };

    systemd.user.services.podcast-audio = lib.mkIf isT14 {
      Unit = {
        Description = "Opt-in podcast programme bus (no microphone or guest loopback)";
        After = [ "pipewire-pulse.service" ];
        Requires = [ "pipewire-pulse.service" ];
        PartOf = [ "pipewire-pulse.service" ];
      };
      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${helper}/bin/obs-podcast-setup audio-start";
        ExecStop = "${helper}/bin/obs-podcast-setup audio-stop";
      };
    };
  }
