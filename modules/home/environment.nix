{
  config,
  ...
}:
let
  npmDir = ".local/share/npm";
  npmPrefix = "${config.home.homeDirectory}/${npmDir}";
in
{
  xdg.enable = true;

  home.sessionVariables = {
    MICRO_TRUECOLOR = "1";
    EDITOR = "hx";
    VISUAL = "hx";
    NIXOS_OZONE_WL = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
    NPM_CONFIG_PREFIX = npmPrefix;
    NODE_PATH = "${npmPrefix}/lib/node_modules";
    PYTHONUSERBASE = "${config.home.homeDirectory}/.local";
    # Persistent tmux may retain local display state and lack SSH markers.
    # Pi should also send copies to the attached terminal (native copy remains).
    PI_CLIPBOARD_OSC52 = "1";

    # Keep Cargo's default workspace-local target directory. The projects
    # tree is a nested btrfs subvolume excluded from home snapshots, and
    # workspace-local artifacts disappear naturally with retired worktrees.
  };

  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.cargo/bin"
    "${npmPrefix}/bin"
  ];

  home.file."${npmDir}/.keep".text = "";
}
