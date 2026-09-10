{ lib, pkgs, ... }:
let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
in
lib.mkIf isLinux {
  home.packages = [ pkgs._1password-gui ];

  xdg.desktopEntries."1password" = {
    name = "1Password";
    comment = "1Password password manager";
    exec = "env ELECTRON_OZONE_PLATFORM_HINT=auto NIXOS_OZONE_WL=1 ${pkgs._1password-gui}/bin/1password %U";
    icon = "1password";
    terminal = false;
    type = "Application";
    categories = [
      "Utility"
      "Security"
      "Network"
    ];
    settings = {
      StartupWMClass = "1Password";
    };
  };
}
