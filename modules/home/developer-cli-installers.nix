{ lib, pkgs, ... }:
let
  installCodex = pkgs.writeShellApplication {
    name = "install-codex-cli";
    runtimeInputs = [ pkgs.curl ];
    text = ''
      if [ -x "$HOME/.local/bin/codex" ]; then
        exit 0
      fi
      echo "Installing Codex CLI with the official standalone installer"
      curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh
    '';
  };
  updateCodex = pkgs.writeShellApplication {
    name = "update-codex-cli";
    runtimeInputs = [ pkgs.curl ];
    text = ''
      echo "Updating Codex CLI with the official standalone installer"
      curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh
    '';
  };
  installClaude = pkgs.writeShellApplication {
    name = "install-claude-code";
    runtimeInputs = [
      pkgs.bash
      pkgs.curl
    ];
    text = ''
      if [ -x "$HOME/.local/bin/claude" ]; then
        exit 0
      fi
      echo "Installing Claude Code from the official stable channel"
      curl -fsSL https://claude.ai/install.sh | bash -s stable
    '';
  };
  retryingService = description: executable: {
    Unit.Description = description;
    Service = {
      Type = "oneshot";
      ExecStart = lib.getExe executable;
      Restart = "on-failure";
      RestartSec = "5m";
    };
    Install.WantedBy = [ "default.target" ];
  };
in
{
  systemd.user.services = {
    codex-cli-install = retryingService "Install Codex CLI after first login" installCodex;
    claude-code-install = retryingService "Install stable Claude Code after first login" installClaude;
    codex-cli-update = {
      Unit.Description = "Update Codex CLI";
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe updateCodex;
      };
    };
  };

  systemd.user.timers.codex-cli-update = {
    Unit.Description = "Randomized weekly Codex CLI update";
    Timer = {
      OnCalendar = "weekly";
      Persistent = true;
      RandomizedDelaySec = "1d";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
