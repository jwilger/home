{
  config,
  jwilgerInputs,
  lib,
  pkgs,
  ...
}:
let
  noctaliaPkg = jwilgerInputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;
  noctaliaBaseline = pkgs.runCommand "noctalia-writable-baseline" { } ''
    mkdir -p "$out/config" "$out/state"
    cp ${./noctalia/config.toml} "$out/config/config.toml"
    cp ${./noctalia/settings.json} "$out/config/settings.json"
    cp ${./noctalia/colors.json} "$out/config/colors.json"
    cp ${./noctalia/plugins.json} "$out/config/plugins.json"
    cp ${./noctalia/settings.toml} "$out/state/settings.toml"
  '';
  wallpaperPath = "${config.home.homeDirectory}/.local/share/wallpapers/wallpaper.png";
  noctaliaWallpaper = pkgs.writeShellApplication {
    name = "noctalia-wallpaper";
    runtimeInputs = [
      noctaliaPkg
      pkgs.coreutils
    ];
    text = ''
      attempt=0
      while [ "$attempt" -lt 100 ]; do
        if noctalia msg wallpaper-set "${wallpaperPath}"; then
          exit 0
        fi

        attempt=$((attempt + 1))
        sleep 0.1
      done

      exit 1
    '';
  };
  lockScreen = pkgs.writeShellScript "lock-screen" ''
    ${pkgs._1password-gui}/bin/1password --lock &
    ${noctaliaPkg}/bin/noctalia msg session lock
  '';
  restoreWindowFocus = pkgs.writeShellApplication {
    name = "restore-window-focus";
    runtimeInputs = [ pkgs.hyprland ];
    text = ''
      hyprctl dispatch 'hl.dsp.focus({ window = hl.get_active_workspace().last_window })'
    '';
  };
in
{
  # Inherit the compositor's environment immediately. Waiting for UWSM's
  # polled environment import exposes the default wallpaper during startup.
  # A transient service retains supervision and ends with the session.
  wayland.windowManager.hyprland.extraConfig = ''
    hl.on("hyprland.start", function()
      hl.exec_cmd(${builtins.toJSON "uwsm app -t service -s background.slice -u noctalia-shell.service -p Restart=on-failure -p PartOf=graphical-session.target -- ${pkgs.coreutils}/bin/env WAYLAND_DISPLAY=\"$WAYLAND_DISPLAY\" HYPRLAND_INSTANCE_SIGNATURE=\"$HYPRLAND_INSTANCE_SIGNATURE\" DISPLAY=\"$DISPLAY\" ${lib.getExe noctaliaPkg}"})
    end)
  '';

  systemd.user.services = {
    noctalia-wallpaper = {
      Unit = {
        Description = "Apply the managed Noctalia wallpaper";
        After = [ "wayland-session-waitenv.service" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${noctaliaWallpaper}/bin/noctalia-wallpaper";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };

  xdg.configFile = {
    "noctalia/assets/nixos.svg".source =
      "${noctaliaPkg}/share/noctalia/assets/images/distros/nixos.svg";
  };

  home.file = {
    ".local/bin/lock-screen".source = lockScreen;
    ".local/share/wallpapers/wallpaper.png".source = ./wallpaper.png;
  };

  home.packages = [
    noctaliaPkg
    restoreWindowFocus
    pkgs.grim
    pkgs.slurp
    pkgs.wl-clipboard
  ];

  home.activation.noctaliaWritableBaseline = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    configDir="$HOME/.config/noctalia"
    stateDir="$HOME/.local/state/noctalia"
    mkdir -p "$configDir" "$stateDir"
    for file in config.toml settings.json colors.json plugins.json; do
      install -m 0600 "${noctaliaBaseline}/config/$file" "$configDir/$file"
    done
    install -m 0600 "${noctaliaBaseline}/state/settings.toml" "$stateDir/settings.toml"
  '';

  home.activation.noctaliaWallpaperSeed = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    cacheFile="$HOME/.cache/noctalia/wallpapers.json"
    mkdir -p "$HOME/.cache/noctalia"
    cacheTempFile="$(mktemp "$HOME/.cache/noctalia/wallpapers.json.XXXXXX")"
    cat > "$cacheTempFile" << 'EOF'
    {
      "defaultWallpaper": "${wallpaperPath}",
      "usedRandomWallpapers": {},
      "wallpapers": {
        "": {
          "dark": "${wallpaperPath}",
          "light": "${wallpaperPath}"
        }
      }
    }
    EOF
    mv "$cacheTempFile" "$cacheFile"
  '';

  home.activation.noctaliaWallpaperLive = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
    ${pkgs.systemd}/bin/systemctl --user start noctalia-wallpaper.service || true
  '';

  home.activation.noctaliaGithubFeed = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p "$HOME/.config/noctalia/plugins/github-feed"
        if command -v op &> /dev/null && op account list &> /dev/null; then
          TOKEN=$(op read "op://Personal/Noctalia GH Notifier PAT/password" 2>/dev/null || echo "")
          if [ -n "$TOKEN" ]; then
            cat > "$HOME/.config/noctalia/plugins/github-feed/settings.json" << EOF
    {
      "username": "jwilger",
      "token": "$TOKEN",
      "refreshInterval": 1800,
      "maxEvents": 50,
      "showStars": true,
      "showForks": true,
      "showPRs": true,
      "showRepoCreations": true,
      "showMyRepoStars": true,
      "showMyRepoForks": true,
      "openInBrowser": true
    }
    EOF
          fi
        fi
  '';
}
