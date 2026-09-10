{
  config,
  lib,
  pkgs,
  ...
}:
let
  isX86_64Linux = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
in
{
  home.packages = (
    with pkgs;
    [
      pavucontrol # pulseaudio volume control (GUI)
    ]
    ++ lib.optionals (isX86_64Linux && config.jwilger.hostProfile == "gregor") [
      discord # chat for games
      gpu-screen-recorder
    ]
  );
}
