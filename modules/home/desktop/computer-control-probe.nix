{
  config,
  lib,
  pkgs,
  ...
}:
let
  probe = pkgs.writeShellApplication {
    name = "hyprland-control-probe";
    runtimeInputs = with pkgs; [
      grim
      wayland-utils
      wtype
      wlrctl
    ];
    text = ''
      exec ${lib.getExe pkgs.python3} ${../../../scripts/hyprland-control-probe.py} "$@"
    '';
  };
in
{
  options.jwilger.computerControlProbe.enable = lib.mkEnableOption "a read-only Hyprland computer-control readiness probe (not computer control)";

  # No services, activation hooks, MCP registration, network listeners or input
  # permissions. hyprctl deliberately comes from the running host's PATH, as
  # the T14's compositor is owned by NixOS, not this Home Manager configuration.
  config = lib.mkIf config.jwilger.computerControlProbe.enable {
    home.packages = [ probe ];
  };
}
