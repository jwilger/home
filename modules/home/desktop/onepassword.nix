{ lib, pkgs, ... }:
let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  personalAccount = "MRECLJED3JFMFCCB6ZS3D5AIZU";
  keyringPasswordReference = "op://Personal/gqwzhhx32czatrq4wckuqzzo5q/password";
  dbusCallTimeoutSec = 15;
  readinessTimeoutSec = 30;
  initialSettleSec = 30;
  approvalTimeoutSec = 180;
  retryBackoffSec = [
    120
    480
  ];
  maxReadAttempts = builtins.length retryBackoffSec + 1;
  postReadDbusCalls = 5;
  killAfterSec = 5;
  timeoutHeadroomSec = 60;
  unlockServiceTimeoutSec =
    initialSettleSec
    + lib.foldl' (total: delay: total + delay) 0 retryBackoffSec
    +
      maxReadAttempts
      * (readinessTimeoutSec + approvalTimeoutSec + postReadDbusCalls * dbusCallTimeoutSec + killAfterSec)
    + timeoutHeadroomSec;
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
  unlockGnomeKeyringFromStdin = pkgs.stdenv.mkDerivation {
    pname = "unlock-gnome-keyring-from-stdin";
    version = "1";
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [ pkgs.libsecret ];
    source = pkgs.writeText "unlock-gnome-keyring-from-stdin.c" ''
      #include <errno.h>
      #include <gio/gio.h>
      #define SECRET_API_SUBJECT_TO_CHANGE 1
      #include <libsecret/secret.h>
      #include <stdbool.h>
      #include <stdio.h>
      #include <string.h>
      #include <unistd.h>

      #define SECRET_SERVICE_NAME "org.freedesktop.secrets"
      #define SECRET_SERVICE_PATH "/org/freedesktop/secrets"
      #define SECRET_SERVICE_INTERFACE "org.freedesktop.Secret.Service"
      #define SECRET_COLLECTION_INTERFACE "org.freedesktop.Secret.Collection"
      #define INTERNAL_INTERFACE "org.gnome.keyring.InternalUnsupportedGuiltRiddenInterface"
      #define DBUS_PROPERTIES_INTERFACE "org.freedesktop.DBus.Properties"
      #define MAX_PASSWORD_BYTES 4096
      #define CALL_TIMEOUT_MSEC ${toString dbusCallTimeoutSec}000
      #define EXIT_COLLECTION_LOCKED 3

      static void
      wipe_memory (void *data,
                   size_t length)
      {
        volatile unsigned char *bytes = data;

        while (length-- > 0)
          *bytes++ = 0;
      }

      static GVariant *
      call_sync (GDBusConnection *connection,
                 const gchar *owner,
                 const gchar *path,
                 const gchar *interface,
                 const gchar *method,
                 GVariant *parameters,
                 const GVariantType *reply_type,
                 GError **error)
      {
        return g_dbus_connection_call_sync (connection,
                                            owner,
                                            path,
                                            interface,
                                            method,
                                            parameters,
                                            reply_type,
                                            G_DBUS_CALL_FLAGS_NO_AUTO_START,
                                            CALL_TIMEOUT_MSEC,
                                            NULL,
                                            error);
      }

      static gboolean
      owner_is_current (GDBusConnection *connection,
                        const gchar *owner,
                        GError **error)
      {
        g_autoptr (GVariant) reply = NULL;
        const gchar *current_owner = NULL;

        reply = call_sync (connection,
                           "org.freedesktop.DBus",
                           "/org/freedesktop/DBus",
                           "org.freedesktop.DBus",
                           "GetNameOwner",
                           g_variant_new ("(s)", SECRET_SERVICE_NAME),
                           G_VARIANT_TYPE ("(s)"),
                           error);
        if (reply == NULL)
          return FALSE;

        g_variant_get (reply, "(&s)", &current_owner);
        return g_strcmp0 (owner, current_owner) == 0;
      }

      static gchar *
      read_login_alias (GDBusConnection *connection,
                        const gchar *owner,
                        GError **error)
      {
        g_autoptr (GVariant) reply = NULL;
        gchar *collection = NULL;

        reply = call_sync (connection,
                           owner,
                           SECRET_SERVICE_PATH,
                           SECRET_SERVICE_INTERFACE,
                           "ReadAlias",
                           g_variant_new ("(s)", "login"),
                           G_VARIANT_TYPE ("(o)"),
                           error);
        if (reply != NULL)
          g_variant_get (reply, "(o)", &collection);

        return collection;
      }

      static gboolean
      read_locked (GDBusConnection *connection,
                   const gchar *owner,
                   const gchar *collection,
                   gboolean *locked,
                   GError **error)
      {
        g_autoptr (GVariant) reply = NULL;
        g_autoptr (GVariant) boxed = NULL;
        g_autoptr (GVariant) value = NULL;

        reply = call_sync (connection,
                           owner,
                           collection,
                           DBUS_PROPERTIES_INTERFACE,
                           "Get",
                           g_variant_new ("(ss)", SECRET_COLLECTION_INTERFACE, "Locked"),
                           G_VARIANT_TYPE ("(v)"),
                           error);
        if (reply == NULL)
          return FALSE;

        g_variant_get (reply, "(@v)", &boxed);
        value = g_variant_get_variant (boxed);
        if (!g_variant_is_of_type (value, G_VARIANT_TYPE_BOOLEAN))
          return FALSE;

        *locked = g_variant_get_boolean (value);
        return TRUE;
      }

      static gboolean
      read_password (unsigned char password[MAX_PASSWORD_BYTES + 1],
                     gsize *length)
      {
        gsize total = 0;

        while (total < MAX_PASSWORD_BYTES + 1) {
          ssize_t count = read (STDIN_FILENO,
                                password + total,
                                MAX_PASSWORD_BYTES + 1 - total);

          if (count > 0) {
            total += (gsize) count;
            continue;
          }
          if (count == 0)
            break;
          if (errno != EINTR)
            return FALSE;
        }

        if (total == 0 || total > MAX_PASSWORD_BYTES)
          return FALSE;

        *length = total;
        return TRUE;
      }

      int
      main (int argc,
            char **argv)
      {
        const gboolean check_only = argc == 2 && strcmp (argv[1], "--check-only") == 0;
        unsigned char password[MAX_PASSWORD_BYTES + 1] = { 0 };
        gsize password_length = 0;
        g_autoptr (GError) error = NULL;
        g_autoptr (SecretService) service = NULL;
        g_autoptr (GDBusConnection) connection = NULL;
        g_autofree gchar *owner = NULL;
        g_autofree gchar *collection = NULL;
        g_autoptr (SecretValue) value = NULL;
        g_autoptr (GVariant) encoded = NULL;
        g_autoptr (GVariant) reply = NULL;
        const gchar *session_algorithm = NULL;
        gboolean locked = TRUE;
        int result = 1;

        if (!check_only && argc != 1)
          goto out;

        service = secret_service_open_sync (SECRET_TYPE_SERVICE,
                                            SECRET_SERVICE_NAME,
                                            SECRET_SERVICE_OPEN_SESSION,
                                            NULL,
                                            &error);
        if (service == NULL)
          goto out;

        connection = g_object_ref (g_dbus_proxy_get_connection (G_DBUS_PROXY (service)));
        owner = g_strdup (g_dbus_proxy_get_name_owner (G_DBUS_PROXY (service)));
        if (owner == NULL || !owner_is_current (connection, owner, &error))
          goto out;

        collection = read_login_alias (connection, owner, &error);
        if (collection == NULL)
          goto out;
        if (!owner_is_current (connection, owner, &error))
          goto out;
        if (strcmp (collection, "/") == 0)
          goto out;

        if (!read_locked (connection, owner, collection, &locked, &error))
          goto out;
        if (!owner_is_current (connection, owner, &error))
          goto out;
        if (!locked) {
          result = 0;
          goto out;
        }
        if (check_only) {
          result = EXIT_COLLECTION_LOCKED;
          goto out;
        }

        if (!read_password (password, &password_length))
          goto out;
        session_algorithm = secret_service_get_session_algorithms (service);
        if (session_algorithm == NULL || g_strcmp0 (session_algorithm, "plain") == 0)
          goto out;

        /* libsecret copies this into non-pageable secure memory and clears it
         * when the SecretValue is released. Clear our stack copy separately. */
        value = secret_value_new ((const gchar *) password,
                                  (gssize) password_length,
                                  "text/plain");
        encoded = secret_service_encode_dbus_secret (service, value);
        secret_value_unref (g_steal_pointer (&value));
        wipe_memory (password, sizeof (password));
        password_length = 0;
        if (encoded == NULL || !owner_is_current (connection, owner, &error))
          goto out;

        reply = call_sync (connection,
                           owner,
                           SECRET_SERVICE_PATH,
                           INTERNAL_INTERFACE,
                           "UnlockWithMasterPassword",
                           g_variant_new ("(o@(oayays))",
                                          collection,
                                          g_steal_pointer (&encoded)),
                           G_VARIANT_TYPE ("()"),
                           &error);
        if (reply == NULL)
          goto out;

        g_clear_pointer (&reply, g_variant_unref);
        if (!owner_is_current (connection, owner, &error))
          goto out;
        if (!read_locked (connection, owner, collection, &locked, &error))
          goto out;
        if (!owner_is_current (connection, owner, &error))
          goto out;
        if (locked)
          goto out;

        result = 0;

      out:
        wipe_memory (password, sizeof (password));
        if (result == 1 && !check_only)
          fputs ("Could not unlock the login keyring.\n", stderr);
        return result;
      }
    '';
    buildPhase = ''
      runHook preBuild
      $CC -std=c11 -O2 -Wall -Wextra -Werror -fstack-protector-strong \
        $(pkg-config --cflags libsecret-1 gio-2.0) \
        "$source" -o unlock-gnome-keyring-from-stdin \
        $(pkg-config --libs libsecret-1 gio-2.0)
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin"
      install -m 0755 unlock-gnome-keyring-from-stdin "$out/bin/"
      runHook postInstall
    '';
  };
  unlockGnomeKeyring = pkgs.writeShellApplication {
    name = "unlock-gnome-keyring-from-1password";
    runtimeInputs = with pkgs; [
      _1password-cli
      coreutils
      libnotify
    ];
    text = ''
      set -euo pipefail

      op_bin=${pkgs._1password-cli}/bin/op
      if [[ -x /run/wrappers/bin/op ]]; then
        op_bin=/run/wrappers/bin/op
      fi
      keyring_helper=${unlockGnomeKeyringFromStdin}/bin/unlock-gnome-keyring-from-stdin
      sleep_bin=${pkgs.coreutils}/bin/sleep
      notify_bin=${pkgs.libnotify}/bin/notify-send

      # ReadAlias, UnlockWithMasterPassword, and the final Locked property
      # check all run in the compiled helper against one unique bus owner.
      # Audited helper source: ${unlockGnomeKeyringFromStdin.source}
      # dbus_call_timeout=${toString dbusCallTimeoutSec}
      # post_read_dbus_calls=${toString postReadDbusCalls}
      # timeout_headroom=${toString timeoutHeadroomSec}
      dbus_call_timeout=${toString dbusCallTimeoutSec}
      readiness_timeout=${toString readinessTimeoutSec}
      initial_settle=${toString initialSettleSec}
      approval_timeout=${toString approvalTimeoutSec}
      kill_after=${toString killAfterSec}
      backoffs=(${lib.concatMapStringsSep " " toString retryBackoffSec})
      max_attempts=${toString maxReadAttempts}

      log_phase() {
        printf 'gnome-keyring-unlock: phase=%s attempt=%s result=%s\n' \
          "$1" "$2" "$3" >&2
      }

      check_keyring() {
        check_timeout="''${1:-$dbus_call_timeout}"
        if ((check_timeout <= 0)); then
          return 1
        fi
        timeout --foreground --kill-after="''${kill_after}s" "$check_timeout" \
          "$keyring_helper" --check-only >/dev/null 2>&1
      }

      wait_for_keyring() {
        readiness_deadline=$((SECONDS + readiness_timeout))
        while ((SECONDS < readiness_deadline)); do
          readiness_remaining=$((readiness_deadline - SECONDS))
          if ((readiness_remaining <= 0)); then
            break
          fi
          check_timeout="$dbus_call_timeout"
          if ((readiness_remaining < check_timeout)); then
            check_timeout="$readiness_remaining"
          fi
          check_status=0
          check_keyring "$check_timeout" || check_status=$?
          if ((check_status == 0 || check_status == 3)); then
            return "$check_status"
          fi
          "$sleep_bin" 2
        done
        return 1
      }

      check_status=0
      check_keyring || check_status=$?
      if ((check_status == 0)); then
        log_phase complete 0 already-unlocked
        exit 0
      fi

      log_phase settle 0 waiting
      "$sleep_bin" "$initial_settle"

      terminal_attempt="$max_attempts"
      terminal_result=exhausted
      for ((attempt = 1; attempt <= max_attempts; attempt++)); do
        check_status=0
        wait_for_keyring || check_status=$?
        if ((check_status == 0)); then
          log_phase complete "$attempt" already-unlocked
          exit 0
        fi
        if ((check_status != 3)); then
          log_phase keyring-readiness "$attempt" unavailable
          terminal_attempt="$attempt"
          terminal_result=unavailable
          break
        fi

        # Each request gets one long authorization window. The retry budget is
        # internal so systemd cannot turn failures into an unbounded prompt
        # loop. 1Password errors are intentionally treated as opaque.
        log_phase read "$attempt" starting
        set +e
        timeout --foreground --kill-after="''${kill_after}s" "$approval_timeout" \
          "$op_bin" read --no-newline \
            --account '${personalAccount}' '${keyringPasswordReference}' 2>/dev/null \
          | "$keyring_helper" 2>/dev/null
        pipeline_status=("''${PIPESTATUS[@]}")
        set -e

        if ((pipeline_status[0] == 0 && pipeline_status[1] == 0)); then
          check_status=0
          check_keyring || check_status=$?
          if ((check_status == 0)); then
            log_phase complete "$attempt" unlocked
            exit 0
          fi
        fi
        log_phase read "$attempt" failed

        if ((attempt < max_attempts)); then
          backoff="''${backoffs[attempt - 1]}"
          log_phase backoff "$attempt" waiting
          "$sleep_bin" "$backoff"
        fi
      done

      log_phase complete "$terminal_attempt" "$terminal_result"
      "$notify_bin" --app-name="GNOME Keyring" \
        "GNOME login keyring remains locked" \
        "Unlock 1Password, then start tenkr-gnome-keyring-unlock-retry.service." \
        >/dev/null 2>&1 || true
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
        Wants = [
          "tenkr-onepassword.service"
          "tenkr-onepassword-cli.service"
        ];
        After = [
          "tenkr-onepassword.service"
          "tenkr-onepassword-cli.service"
        ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Environment = [
          "OP_BIOMETRIC_UNLOCK_ENABLED=true"
          "OP_SOCK=%t/onepassword/op-daemon.sock"
        ];
        Type = "oneshot";
        ExecStart = "${unlockGnomeKeyring}/bin/unlock-gnome-keyring-from-1password";
        TimeoutStartSec = unlockServiceTimeoutSec;
        LimitCORE = 0;
      };
    };

    tenkr-gnome-keyring-unlock-launch = {
      Unit = {
        Description = "Launch GNOME Keyring recovery for this graphical session";
        Wants = [
          "tenkr-onepassword.service"
          "tenkr-onepassword-cli.service"
        ];
        After = [
          "tenkr-onepassword.service"
          "tenkr-onepassword-cli.service"
        ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/systemctl --user start --no-block tenkr-gnome-keyring-unlock.service";
        RemainAfterExit = true;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    tenkr-gnome-keyring-unlock-retry = {
      Unit.Description = "Retry unlocking GNOME Keyring from 1Password";
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/systemctl --user start --no-block tenkr-gnome-keyring-unlock.service";
      };
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
