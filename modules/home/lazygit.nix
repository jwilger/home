{ pkgs, ... }:
{
  programs.lazygit = {
    enable = true;
    settings = {
      # Lazygit shell-quotes {{text}}. Write OSC 52 to the controlling terminal,
      # not captured command stdout or a stale server-local Wayland clipboard.
      os.copyToClipboardCmd = ''printf '\033]52;c;%s\a' "$(printf '%s' {{text}} | ${pkgs.coreutils}/bin/base64 -w0)" > /dev/tty'';
      gui = {
        # Use catppuccin theme colors to match the rest of the system
        theme = {
          activeBorderColor = [
            "lavender"
            "bold"
          ];
          inactiveBorderColor = [ "overlay0" ];
          optionsTextColor = [ "blue" ];
          selectedLineBgColor = [ "surface0" ];
          cherryPickedCommitBgColor = [ "base" ];
          cherryPickedCommitFgColor = [ "blue" ];
          unstagedChangesColor = [ "red" ];
          defaultFgColor = [ "text" ];
        };
        showIcons = true;
      };
      git = {
        # Lazygit 0.46+ replaced `paging` (object) with `pagers` (array).
        # Old single-pager config wrapped into a one-element array.
        pagers = [
          {
            colorArg = "always";
            pager = "delta --dark --paging=never";
          }
        ];
        merging = {
          manualCommit = false;
          args = "";
        };
      };
      update = {
        method = "never"; # Disable auto-updates since we manage through Nix
      };
      confirmOnQuit = false;
      quitOnTopLevelReturn = true;
    };
  };
}
