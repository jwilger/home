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
    cp ${./noctalia/settings.toml} "$out/state/settings.toml"
  '';
  wallpaperPath = "${config.home.homeDirectory}/.local/share/wallpapers/wallpaper.png";
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
    install -m 0600 "${noctaliaBaseline}/config/config.toml" "$configDir/config.toml"
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
