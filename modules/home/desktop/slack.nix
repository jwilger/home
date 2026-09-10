{ lib, pkgs, ... }:
let
  isAarch64Linux = pkgs.stdenv.hostPlatform.system == "aarch64-linux";
  isX86_64Linux = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
in
lib.mkMerge [
  (lib.mkIf isAarch64Linux {
    home.packages = [ pkgs.slacky ];

    xdg.desktopEntries.slacky = {
      name = "Slacky";
      comment = "Unofficial Slack desktop client for arm64 Linux";
      exec = "env NIXOS_OZONE_WL=1 ${lib.getExe pkgs.slacky} %U";
      icon = "slacky";
      terminal = false;
      type = "Application";
      categories = [
        "Network"
        "InstantMessaging"
      ];
      mimeType = [ "x-scheme-handler/slack" ];
      settings.StartupWMClass = "com.andersonlaverde.slacky";
    };

    programs.zsh.shellAliases.slack = "NIXOS_OZONE_WL=1 ${lib.getExe pkgs.slacky}";
  })
  (lib.mkIf isX86_64Linux {
    home.packages = [ pkgs.slack ];

    xdg.desktopEntries.slack = {
      name = "Slack";
      comment = "Slack Desktop client";
      exec = "env NIXOS_OZONE_WL=1 ${pkgs.slack}/bin/slack --enable-features=UseOzonePlatform --ozone-platform=wayland %U";
      icon = "slack";
      terminal = false;
      type = "Application";
      categories = [
        "Network"
        "InstantMessaging"
        "Office"
      ];
      mimeType = [
        "x-scheme-handler/slack"
        "x-scheme-handler/slack-ssb"
        "x-scheme-handler/slack-calls"
      ];
      settings = {
        StartupWMClass = "Slack";
      };
    };

    programs.zsh.shellAliases.slack = "NIXOS_OZONE_WL=1 ${pkgs.slack}/bin/slack --enable-features=UseOzonePlatform --ozone-platform=wayland";
  })
]
