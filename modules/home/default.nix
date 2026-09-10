{
  config,
  lib,
  ...
}:
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
    programs.home-manager.enable = true;
    programs.lanyard-ssh-agent.enable = config.jwilger.hostProfile == "gregor";
  };
}
