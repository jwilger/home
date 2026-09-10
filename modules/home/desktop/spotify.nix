{ lib, pkgs, ... }:
let
  isX86_64Linux = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
in
lib.mkIf isX86_64Linux {
  # Official Spotify desktop client
  home.packages = with pkgs; [
    spotify
  ];

  # Terminal-based Spotify client with full Home Manager integration
  programs.spotify-player = {
    enable = true;
    settings = {
      # Copy commands for sharing tracks (using wl-copy for Wayland)
      copy_command = {
        command = "wl-copy";
        args = [ ];
      };

      # Audio and playback settings
      device = {
        audio_cache = true;
        audio_cache_size = 1000000000; # 1GB cache
        normalization = false;
        bitrate = 320;
        # Use persistent cache location
        cache_path = "$HOME/.cache/spotify-player";
      };

      # UI preferences
      playback_window_position = "Top";
      playback_format = "$track - $artists [$duration]";
    };
  };

  # Background Spotify Connect daemon service
  services.spotifyd = {
    enable = true;
    settings = {
      global = {
        # Device identification
        device_name = "NixOS-Desktop";
        device_type = "computer";

        # Audio quality settings
        bitrate = 320;
        volume_normalisation = true;
        normalisation_pregain = -10;

        # Cache and performance - use persistent location
        cache_path = "$HOME/.cache/spotifyd";
        no_audio_cache = false;
        max_cache_size = 1000000000; # 1GB cache

        # Backend configuration for Linux audio - use PulseAudio for PipeWire compatibility
        backend = "pulseaudio";

        # Authentication using 1Password CLI
        username_cmd = "op read op://Personal4Real/spotify.com/username";
        password_cmd = "op read op://Personal4Real/spotify.com/password";
      };
    };
  };
}
