{ lib, pkgs, ... }:
lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
  home.packages = [
    pkgs.voxtype
    pkgs.wtype
  ];

  # The model is downloaded separately with `voxtype setup --download`.
  # Noctalia's notification daemon displays the recording/transcription state.
  xdg.configFile."voxtype/config.toml".text = ''
    state_file = "auto"

    [hotkey]
    enabled = false

    [whisper]
    model = "base.en"
    language = "en"

    [output]
    mode = "type"
    fallback_to_clipboard = true

    [output.notification]
    on_recording_start = true
    on_recording_stop = true
    on_transcription = false
  '';

  # Started by Hyprland so direct and UWSM sessions behave the same. UWSM
  # stops the service with graphical-session.target at logout.
  systemd.user.services.voxtype = {
    Unit = {
      Description = "Voxtype speech-to-text daemon";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${lib.getExe pkgs.voxtype}";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };
}
