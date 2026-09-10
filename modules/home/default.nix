{
  config,
  jwilgerInputs,
  lib,
  pkgs,
  ...
}:
let
  upstreamHomeManager =
    jwilgerInputs.home-manager.packages.${pkgs.stdenv.hostPlatform.system}.default;
  remoteHomeManager = pkgs.writeShellApplication {
    name = "home-manager";
    text = ''
      is_switch=false
      has_flake=false

      for arg in "$@"; do
        case "$arg" in
          switch) is_switch=true ;;
          --flake | --flake=*) has_flake=true ;;
        esac
      done

      if [[ "$is_switch" == true && "$has_flake" == false ]]; then
        set -- "$@" --flake ${lib.escapeShellArg "github:jwilger/home#jwilger@${config.jwilger.hostProfile}"}
      fi

      exec ${lib.getExe upstreamHomeManager} "$@"
    '';
  };
in
{
  imports = [
    ./abduco.nix
    ./ai-bot
    ./aws.nix
    ./bat.nix
    ./btop.nix
    ./codex-session-retention.nix
    ./development-storage.nix
    ./developer-cli-installers.nix
    ./environment.nix
    ./git.nix
    ./helix
    ./lazygit.nix
    ./lanyard.nix
    ./packages.nix
    ./ssh.nix
    ./starship.nix
    ./theme.nix
    ./tmux.nix
    ./voice-dictation.nix
    ./wezterm.nix
    ./yazi
    ./zellij
    ./zsh.nix
    ./desktop
  ];

  options.jwilger.hostProfile = lib.mkOption {
    type = lib.types.nullOr (
      lib.types.enum [
        "gregor"
        "jwilger-t14"
      ]
    );
    default = null;
    description = "Host-specific behavior for John Wilger's shared home configuration.";
  };

  config = {
    assertions = [
      {
        assertion = config.jwilger.hostProfile != null;
        message = "jwilger.hostProfile must be set to gregor or jwilger-t14";
      }
    ];

    home.stateVersion = "24.11";
    home.packages = [ (lib.hiPrio remoteHomeManager) ];
    programs.home-manager.enable = true;
    programs.lanyard-ssh-agent.enable = config.jwilger.hostProfile == "gregor";
  };
}
