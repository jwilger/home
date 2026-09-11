{ lib, pkgs, ... }:
let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  personalAccount = "MRECLJED3JFMFCCB6ZS3D5AIZU";
  keyringPasswordReference = "op://Personal/gqwzhhx32czatrq4wckuqzzo5q/password";
  onePasswordCliDaemon = pkgs.writeShellApplication {
    name = "onepassword-cli-daemon";
    runtimeInputs = [ pkgs._1password-cli ];
    text = ''
      # NixOS installs `op` as a setgid wrapper. Use it explicitly so the
      # desktop app can authenticate the daemon's IPC peer. The store binary
      # remains a portable fallback on Linux systems without that wrapper.
      if [[ -x /run/wrappers/bin/op ]]; then
        exec /run/wrappers/bin/op daemon --timeout 0
      fi

      exec ${pkgs._1password-cli}/bin/op daemon --timeout 0
    '';
  };
  unlockGnomeKeyring = pkgs.writeShellApplication {
    name = "unlock-gnome-keyring-from-1password";
    runtimeInputs = with pkgs; [
      _1password-cli
      coreutils
      gnome-keyring
    ];
    text = ''
      set -euo pipefail

      # The desktop app may still be starting, or may need the user to
      # approve its authentication prompt. Retry without ever writing the
      # password to a file or to the journal.
      op_bin=${pkgs._1password-cli}/bin/op
      if [[ -x /run/wrappers/bin/op ]]; then
        op_bin=/run/wrappers/bin/op
      fi

      for ((attempt = 1; attempt <= 60; attempt++)); do
        if timeout --foreground 15s "$op_bin" read --no-newline \
          --account '${personalAccount}' '${keyringPasswordReference}' \
          | gnome-keyring-daemon --unlock >/dev/null 2>/dev/null; then
          exit 0
        fi
        sleep 5
      done

      echo "Unable to unlock GNOME Keyring from 1Password after waiting for the desktop app." >&2
      exit 1
    '';
  };
in
lib.mkIf isLinux {
  home.packages = [ pkgs._1password-gui ];

  # Keep these names aligned with the workstation's existing user-service
  # contract. Home Manager's per-user units override the system-provided
  # conditional versions and avoid their graphical-session ordering cycle.
  systemd.user.services = {
    tenkr-onepassword = {
      Unit = {
        Description = "Start 1Password for CLI-integrated desktop sessions";
        After = [ "wayland-session-waitenv.service" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Environment = [
          "ELECTRON_OZONE_PLATFORM_HINT=auto"
          "NIXOS_OZONE_WL=1"
        ];
        ExecStart = "${pkgs._1password-gui}/bin/1password --silent";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    tenkr-onepassword-cli = {
      Unit = {
        Description = "Keep the 1Password CLI daemon available to the desktop app";
        Wants = [ "tenkr-onepassword.service" ];
        After = [ "tenkr-onepassword.service" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Environment = [ "OP_SOCK=%t/onepassword/op-daemon.sock" ];
        ExecStart = "${onePasswordCliDaemon}/bin/onepassword-cli-daemon";
        Restart = "on-failure";
        RestartSec = 2;
        RuntimeDirectory = "onepassword";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    tenkr-gnome-keyring-unlock = {
      Unit = {
        Description = "Unlock GNOME Keyring using a password stored in 1Password";
        Wants = [ "tenkr-onepassword-cli.service" ];
        After = [ "tenkr-onepassword-cli.service" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Environment = [
          "OP_BIOMETRIC_UNLOCK_ENABLED=true"
          "OP_SOCK=%t/onepassword/op-daemon.sock"
        ];
        Type = "oneshot";
        ExecStart = "${unlockGnomeKeyring}/bin/unlock-gnome-keyring-from-1password";
        Restart = "on-failure";
        RestartSec = 10;
        TimeoutStartSec = 330;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };

  xdg.desktopEntries."1password" = {
    name = "1Password";
    comment = "1Password password manager";
    exec = "env ELECTRON_OZONE_PLATFORM_HINT=auto NIXOS_OZONE_WL=1 ${pkgs._1password-gui}/bin/1password %U";
    icon = "1password";
    terminal = false;
    type = "Application";
    categories = [
      "Utility"
      "Security"
      "Network"
    ];
    settings = {
      StartupWMClass = "1Password";
    };
  };
}
