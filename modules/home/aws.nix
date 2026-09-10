{ jwilgerInputs, pkgs, ... }:
{
  programs.awscli = {
    enable = true;
    # Use nixos-unstable-small to avoid awscli2 2.30.6 build hang bug
    # Fixed in 2.31.11 which is available in nixos-unstable-small
    package = jwilgerInputs.nixpkgs-small.legacyPackages.${pkgs.stdenv.hostPlatform.system}.awscli2;
  };
}
