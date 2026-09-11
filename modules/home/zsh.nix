{
  config,
  lib,
  pkgs,
  ...
}:
{
  programs.zsh = {
    enable = true;
    dotDir = "${config.xdg.configHome}/zsh";
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
        "fzf"
        "sudo"
        "1password"
        "aws"
        "colored-man-pages"
        "docker"
        "docker-compose"
        "gh"
        "git-auto-fetch"
        "git-commit"
        "npm"
        "postgres"
        "rust"
        "safe-paste"
        "eza"
      ];
    };

    initContent = lib.mkMerge [
      (lib.mkOrder 500 ''
        # Oh My Zsh's Docker plugin copies a completion from the immutable Nix
        # store, preserving its read-only mode, and refreshes it on later starts.
        for completion in ''${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-zsh/completions/*(N); do
          [[ -O "$completion" && ! -w "$completion" ]] && chmod u+w -- "$completion"
        done
        unset completion
      '')
      (lib.mkOrder 1000 ''
        if [[ -n "$SSH_CONNECTION" ]]; then
            export OP_BIOMETRIC_UNLOCK_ENABLED=false
        fi

        # Zellij 0.43.1+ natively manages terminal title with session name.
        # Shell-based title setting is disabled as zellij intercepts OSC sequences.
        # See: https://github.com/zellij-org/zellij/pull/3898 for session-switch title fix.
      '')
    ];

    shellAliases = {
      # Utils
      cat = "bat";
      open = "xdg-open";

      # Nixos
      ns = "nix-shell --run zsh";
      nix-shell = "nix-shell --run zsh";
      nix-clean = "sudo nix-collect-garbage && sudo nix-collect-garbage -d && sudo rm /nix/var/nix/gcroots/auto/* && nix-collect-garbage && nix-collect-garbage -d";

      # Git
      g = "git";
      ga = "git add";
      gaa = "git add --all";
      gst = "git status";
      gbr = "git branch";
      gpl = "git pull";
      gps = "git push";
      gci = "git commit";
      gco = "git checkout";
    }
    // lib.optionalAttrs (config.jwilger.hostProfile == "gregor") {
      nix-switch = "sudo nixos-rebuild switch --flake /etc/nixos#gregor";
      nix-switchu = "sudo nixos-rebuild switch --upgrade --flake /etc/nixos#gregor";
    }
    // lib.optionalAttrs (config.jwilger.hostProfile == "jwilger-t14") {
      fleet-update = "sudo tenkr-fleet-update";
      fleet-status = "systemctl status tenkr-fleet-update.service tenkr-fleet-update.timer";
    };
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };
}
