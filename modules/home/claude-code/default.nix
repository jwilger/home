{
  lib,
  pkgs,
  ...
}:
let
  statusLine = pkgs.writeShellApplication {
    name = "claude-statusline";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
      pkgs.jq
    ];
    text = builtins.readFile ./statusline.sh;
  };
  # Claude Code, its `claude mcp add`/plugin installers and the Hindsight
  # installer all write settings.json, so it cannot be a store symlink.
  # Activation owns only the statusLine key and leaves the rest alone.
  applySettings = pkgs.writeShellApplication {
    name = "apply-claude-code-settings";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.diffutils
      pkgs.jq
    ];
    text = ''
      settings="$HOME/.claude/settings.json"
      mkdir -p "$(dirname "$settings")"
      if [[ ! -s "$settings" ]]; then
        (umask 077 && printf '{}\n' > "$settings")
      fi
      settings_tmp="$(mktemp "$(dirname "$settings")/.settings.XXXXXX")"
      trap 'rm -f -- "$settings_tmp"' EXIT
      jq --arg command ${lib.escapeShellArg (lib.getExe statusLine)} \
        '.statusLine = {type: "command", command: $command}' \
        "$settings" > "$settings_tmp"
      if cmp -s "$settings_tmp" "$settings"; then
        exit 0
      fi
      chmod --reference="$settings" "$settings_tmp"
      mv -- "$settings_tmp" "$settings"
    '';
  };
in
{
  options.jwilger.claudeCode = {
    statusLine = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = "Claude Code status line command.";
    };
    applySettings = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = "Merge Home Manager-owned keys into the writable Claude Code settings.json.";
    };
  };
  config = {
    jwilger.claudeCode = { inherit statusLine applySettings; };
    home.activation.claudeCodeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe applySettings}
    '';
  };
}
