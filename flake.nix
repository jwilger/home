{
  description = "John Wilger's shared Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-small.url = "github:NixOS/nixpkgs/nixos-unstable-small";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin.url = "github:catppuccin/nix";
    catppuccin-starship = {
      url = "github:catppuccin/starship";
      flake = false;
    };
    lanyard = {
      url = "github:jwilger/lanyard-ssh-agent/v0.1.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    noctalia.url = "github:noctalia-dev/noctalia/cachix";
    zjstatus.url = "github:dj95/zjstatus/053898e1e245c0df9aaaa783710e88e2926fbbb2";
  };

  outputs =
    inputs@{
      catppuccin,
      home-manager,
      nixpkgs,
      self,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      mkHome =
        hostProfile:
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = { inherit inputs; };
          modules = [
            self.homeModules.jwilger
            {
              jwilger.hostProfile = hostProfile;
              home = {
                username = "jwilger";
                homeDirectory = "/home/jwilger";
              };
            }
          ];
        };
    in
    {
      homeModules = {
        jwilger = {
          imports = [
            inputs.catppuccin.homeModules.catppuccin
            ./modules/home
          ];
          _module.args.jwilgerInputs = inputs;
        };
        default = self.homeModules.jwilger;
      };

      homeConfigurations = {
        "jwilger@gregor" = mkHome "gregor";
        "jwilger@jwilger-t14" = mkHome "jwilger-t14";
      };

      checks.${system} = {
        gregor = self.homeConfigurations."jwilger@gregor".activationPackage;
        jwilger-t14 = self.homeConfigurations."jwilger@jwilger-t14".activationPackage;
        noctalia-startup-order = pkgs.runCommand "check-noctalia-startup-order" { } ''
          homeFiles=${self.homeConfigurations."jwilger@jwilger-t14".activationPackage}/home-files
          userUnits="$homeFiles/.config/systemd/user"

          test -L "$userUnits/graphical-session.target.wants/noctalia-hyprland.service"
          test -L "$userUnits/graphical-session.target.wants/noctalia-wallpaper.service"
          grep -Fqx 'After=wayland-session-waitenv.service' "$userUnits/noctalia-hyprland.service"
          grep -Fqx 'PartOf=graphical-session.target' "$userUnits/noctalia-hyprland.service"
          grep -Fqx 'Wants=noctalia-hyprland.service' "$userUnits/noctalia-wallpaper.service"
          grep -Fqx 'After=noctalia-hyprland.service' "$userUnits/noctalia-wallpaper.service"
          ! grep -Fq 'noctalia-shell.service' "$homeFiles/.config/hypr/hyprland.lua"

          touch "$out"
        '';
        hyprland-catppuccin-borders = pkgs.runCommand "check-hyprland-catppuccin-borders" { } ''
          hyprlandConfig=${
            self.homeConfigurations."jwilger@jwilger-t14".activationPackage
          }/home-files/.config/hypr/hyprland.lua

          grep -Fq '["active_border"] = "rgb(cba6f7)"' "$hyprlandConfig"
          grep -Fq '["inactive_border"] = "rgb(1e1e2e)"' "$hyprlandConfig"
          grep -Fq '["border_active"] = "rgb(fab387)"' "$hyprlandConfig"
          grep -Fq '["border_inactive"] = "rgb(1e1e2e)"' "$hyprlandConfig"
          grep -Fq '["border_locked_active"] = "rgb(f38ba8)"' "$hyprlandConfig"
          grep -Fq '["border_locked_inactive"] = "rgb(1e1e2e)"' "$hyprlandConfig"

          touch "$out"
        '';
        interface =
          assert self.homeModules.default == self.homeModules.jwilger;
          pkgs.emptyDirectory;
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
