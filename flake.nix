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
        noctalia-startup-order = pkgs.runCommand "check-noctalia-startup" { } ''
          homeFiles=${self.homeConfigurations."jwilger@jwilger-t14".activationPackage}/home-files
          hyprlandConfig="$homeFiles/.config/hypr/hyprland.lua"
          noctaliaConfig=${./modules/home/desktop/noctalia/config.toml}

          grep -Fq 'hl.on("hyprland.start"' "$hyprlandConfig"
          grep -Fq 'noctalia --daemon' "$hyprlandConfig"
          grep -Fq '["disable_hyprland_logo"] = true' "$hyprlandConfig"
          grep -Fq 'transition_on_startup = false' "$noctaliaConfig"
          test ! -e "$homeFiles/.config/systemd/user/noctalia-hyprland.service"
          test ! -e "$homeFiles/.config/systemd/user/noctalia-wallpaper.service"

          touch "$out"
        '';
        onepassword-startup = pkgs.runCommand "check-onepassword-startup" { } ''
          homeFiles=${self.homeConfigurations."jwilger@jwilger-t14".activationPackage}/home-files
          hyprlandConfig="$homeFiles/.config/hypr/hyprland.lua"
          onepasswordService="$homeFiles/.config/systemd/user/tenkr-onepassword.service"
          onepasswordCliService="$homeFiles/.config/systemd/user/tenkr-onepassword-cli.service"
          keyringService="$homeFiles/.config/systemd/user/tenkr-gnome-keyring-unlock.service"
          unlockScript="$(sed -n 's/^ExecStart=//p' "$keyringService")"

          test ! -e "$hyprlandConfig" || ! grep -Fq '1password --silent' "$hyprlandConfig"
          test ! -e "$hyprlandConfig" || ! grep -Fq 'op read --no-newline' "$hyprlandConfig"
          grep -Fq 'After=wayland-session-waitenv.service' "$onepasswordService"
          ! grep -Eq '^After=([^[:space:]]+[[:space:]]+)*graphical-session\.target([[:space:]]|$)' "$onepasswordService"
          grep -Fq '1password --silent' "$onepasswordService"
          grep -Fq 'Wants=tenkr-onepassword.service' "$onepasswordCliService"
          grep -Fq 'OP_SOCK=%t/onepassword/op-daemon.sock' "$onepasswordCliService"
          grep -Fq 'onepassword-cli-daemon' "$onepasswordCliService"
          grep -Fq 'Wants=tenkr-onepassword-cli.service' "$keyringService"
          grep -Fq 'After=tenkr-onepassword-cli.service' "$keyringService"
          grep -Fq 'PartOf=graphical-session.target' "$keyringService"
          grep -Fq 'WantedBy=graphical-session.target' "$keyringService"
          test -x "$unlockScript"
          grep -Fq 'read --no-newline' "$unlockScript"
          grep -Fq -- "--account 'MRECLJED3JFMFCCB6ZS3D5AIZU'" "$unlockScript"
          grep -Fq 'op://Personal/gqwzhhx32czatrq4wckuqzzo5q/password' "$unlockScript"
          grep -Fq 'gnome-keyring-daemon --unlock' "$unlockScript"

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
