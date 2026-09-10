{ pkgs, ... }:
{
  # VLC media player with all codecs
  home.packages = with pkgs; [
    vlc
  ];
}
