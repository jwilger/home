{ pkgs, lib, ... }:
{
  programs.btop = {
    enable = true;

    settings = {
      theme_background = false;
      update_ms = 500;
    };
  };

  home.packages = lib.optionals pkgs.stdenv.isLinux (
    with pkgs;
    [
      nvtopPackages.intel
    ]
  );
}
