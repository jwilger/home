{ lib, pkgs, ... }:
let
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
    claude-code-install = retryingService "Install stable Claude Code after first login" installClaude;
  };
}
