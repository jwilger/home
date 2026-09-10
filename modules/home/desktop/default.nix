{ ... }:
{
  imports = [
    (import ./chatgpt.nix)
    (import ./claude-desktop.nix)
    (import ./hyprland.nix)
    (import ./insync)
    (import ./nignite.nix)
    (import ./noctalia.nix)
    (import ./onepassword.nix)
    (import ./spotify.nix)
    (import ./slack.nix)
    (import ./vlc.nix)
    (import ./zoom.nix)
    (import ./packages.nix)
    (import ./obs-studio.nix)
  ];
}
