{
  description = "John Wilger's shared Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-small.url = "github:NixOS/nixpkgs/nixos-unstable-small";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin.url = "github:catppuccin/nix";
    catppuccin-starship = {
      url = "github:catppuccin/starship";
      flake = false;
    };
    lanyard = {
      url = "github:jwilger/lanyard-ssh-agent/v0.1.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    noctalia.url = "github:noctalia-dev/noctalia/cachix";
    zjstatus.url = "github:dj95/zjstatus/053898e1e245c0df9aaaa783710e88e2926fbbb2";
  };

  outputs =
    inputs@{
      catppuccin,
      home-manager,
      nixpkgs,
      self,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      mkHome =
        hostProfile:
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = { inherit inputs; };
          modules = [
            self.homeModules.jwilger
            {
              jwilger.hostProfile = hostProfile;
              home = {
                username = "jwilger";
                homeDirectory = "/home/jwilger";
              };
            }
          ];
        };
    in
    {
      homeModules = {
        jwilger = {
          imports = [
            inputs.catppuccin.homeModules.catppuccin
            ./modules/home
          ];
          _module.args.jwilgerInputs = inputs;
        };
        default = self.homeModules.jwilger;
      };

      homeConfigurations = {
        "jwilger@gregor" = mkHome "gregor";
        "jwilger@jwilger-t14" = mkHome "jwilger-t14";
      };

      checks.${system} = {
        gregor = self.homeConfigurations."jwilger@gregor".activationPackage;
        jwilger-t14 = self.homeConfigurations."jwilger@jwilger-t14".activationPackage;
        noctalia-startup-order = pkgs.runCommand "check-noctalia-startup" { } ''
          homeFiles=${self.homeConfigurations."jwilger@jwilger-t14".activationPackage}/home-files
          hyprlandConfig="$homeFiles/.config/hypr/hyprland.lua"
          noctaliaConfig=${./modules/home/desktop/noctalia/config.toml}

          grep -Fq 'hl.on("hyprland.start"' "$hyprlandConfig"
          grep -Fq 'noctalia --daemon' "$hyprlandConfig"
          grep -Fq '["disable_hyprland_logo"] = true' "$hyprlandConfig"
          grep -Fq 'transition_on_startup = false' "$noctaliaConfig"
          test ! -e "$homeFiles/.config/systemd/user/noctalia-hyprland.service"
          test ! -e "$homeFiles/.config/systemd/user/noctalia-wallpaper.service"

          touch "$out"
        '';
        onepassword-startup =
          let
            semanticTest = pkgs.writeShellScript "onepassword-keyring-semantic-test" ''
              set -euo pipefail

              helper="$1"
              test_root="$TMPDIR/keyring-semantic"
              export HOME="$test_root/home"
              export XDG_CONFIG_HOME="$HOME/.config"
              export XDG_DATA_HOME="$HOME/.local/share"
              export XDG_RUNTIME_DIR="$test_root/runtime"
              mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_RUNTIME_DIR"
              chmod 700 "$HOME" "$XDG_RUNTIME_DIR"

              daemon_pid=
              stop_daemon() {
                if [[ -n "$daemon_pid" ]]; then
                  kill "$daemon_pid" 2>/dev/null || true
                  wait "$daemon_pid" 2>/dev/null || true
                  daemon_pid=
                fi
              }
              trap stop_daemon EXIT

              start_daemon() {
                if [[ "$1" == --initialize ]]; then
                  printf '%s' fixture-pass \
                    | ${pkgs.gnome-keyring}/bin/gnome-keyring-daemon \
                      --foreground --components=secrets --unlock \
                      >"$test_root/daemon.log" 2>&1 &
                else
                  ${pkgs.gnome-keyring}/bin/gnome-keyring-daemon \
                    --foreground --components=secrets \
                    >"$test_root/daemon.log" 2>&1 &
                fi
                daemon_pid=$!
                for _ in $(seq 1 100); do
                  if ${pkgs.glib}/bin/gdbus call --session \
                    --dest org.freedesktop.DBus \
                    --object-path /org/freedesktop/DBus \
                    --method org.freedesktop.DBus.NameHasOwner \
                    org.freedesktop.secrets 2>/dev/null | grep -Fq true; then
                    return 0
                  fi
                  sleep 0.05
                done
                return 1
              }

              start_daemon --initialize
              "$helper" --check-only
              stop_daemon
              start_daemon --locked

              set +e
              "$helper" --check-only
              check_status=$?
              set -e
              test "$check_status" -eq 3

              # Wait until the helper has linearized the initial Locked=true
              # reply and is blocked reading stdin, then replace the service
              # owner. The password must not be sent to the replacement owner.
              coproc TAKEOVER_HELPER {
                exec "$helper" >"$test_root/takeover.stdout" 2>"$test_root/takeover.stderr"
              }
              takeover_pid=$TAKEOVER_HELPER_PID
              takeover_input_fd="''${TAKEOVER_HELPER[1]}"
              waiting_for_password=false
              for _ in $(seq 1 100); do
                if grep -Fq pipe_read "/proc/$takeover_pid/wchan" 2>/dev/null; then
                  waiting_for_password=true
                  break
                fi
                sleep 0.05
              done
              test "$waiting_for_password" = true
              stop_daemon
              start_daemon --locked
              printf '%s' fixture-pass >&"$takeover_input_fd"
              exec {takeover_input_fd}>&-
              set +e
              wait "$takeover_pid"
              takeover_status=$?
              set -e
              test "$takeover_status" -ne 0
              set +e
              "$helper" --check-only
              check_status=$?
              set -e
              test "$check_status" -eq 3

              if printf '%s' wrong-password \
                | "$helper" >"$test_root/wrong.stdout" 2>"$test_root/wrong.stderr"; then
                exit 1
              fi
              set +e
              "$helper" --check-only
              check_status=$?
              set -e
              test "$check_status" -eq 3

              if printf '%s' "" \
                | "$helper" >"$test_root/empty.stdout" 2>"$test_root/empty.stderr"; then
                exit 1
              fi
              set +e
              "$helper" --check-only
              check_status=$?
              set -e
              test "$check_status" -eq 3

              if head -c 4097 /dev/zero \
                | tr '\\0' x \
                | "$helper" >"$test_root/oversized.stdout" 2>"$test_root/oversized.stderr"; then
                exit 1
              fi
              set +e
              "$helper" --check-only
              check_status=$?
              set -e
              test "$check_status" -eq 3

              printf '%s' fixture-pass \
                | "$helper" >"$test_root/success.stdout" 2>"$test_root/success.stderr"
              "$helper" --check-only

              test ! -s "$test_root/success.stdout"
              test ! -s "$test_root/takeover.stdout"
              test ! -s "$test_root/wrong.stdout"
              test ! -s "$test_root/empty.stdout"
              test ! -s "$test_root/oversized.stdout"
              test ! -s "$test_root/success.stderr"
              for error_output in \
                "$test_root/takeover.stderr" \
                "$test_root/wrong.stderr" \
                "$test_root/empty.stderr" \
                "$test_root/oversized.stderr"; do
                grep -Fxq 'Could not unlock the login keyring.' "$error_output"
                test "$(wc -l < "$error_output")" -eq 1
              done
              for output in \
                "$test_root/daemon.log" \
                "$test_root/takeover.stdout" "$test_root/takeover.stderr" \
                "$test_root/wrong.stdout" "$test_root/wrong.stderr" \
                "$test_root/empty.stdout" "$test_root/empty.stderr" \
                "$test_root/oversized.stdout" "$test_root/oversized.stderr" \
                "$test_root/success.stdout" "$test_root/success.stderr"; do
                if grep -Fq fixture-pass "$output"; then
                  exit 1
                fi
              done
            '';
            recoveryOp = pkgs.writeShellScript "onepassword-recovery-test-op" ''
              set -euo pipefail

              count_file="$RECOVERY_TEST_ROOT/op-count"
              count=0
              if [[ -e "$count_file" ]]; then
                count="$(<"$count_file")"
              fi
              count=$((count + 1))
              printf '%s\n' "$count" >"$count_file"

              if [[ "$RECOVERY_TEST_SCENARIO" == third-success && "$count" -eq 3 ]] \
                || [[ "$RECOVERY_TEST_SCENARIO" == readiness-recovery && "$count" -eq 1 ]]; then
                printf '%s' recovery-fixture-secret
                exit 0
              fi
              exit 1
            '';
            recoveryHelper = pkgs.writeShellScript "onepassword-recovery-test-helper" ''
              set -euo pipefail

              if [[ "''${1-}" == --check-only ]]; then
                check_count_file="$RECOVERY_TEST_ROOT/check-count"
                check_count=0
                if [[ -e "$check_count_file" ]]; then
                  check_count="$(<"$check_count_file")"
                fi
                check_count=$((check_count + 1))
                printf '%s\n' "$check_count" >"$check_count_file"
                if [[ -e "$RECOVERY_TEST_ROOT/unlocked" ]]; then
                  exit 0
                fi
                if [[ "$RECOVERY_TEST_SCENARIO" == deadline-rollover ]]; then
                  exit 1
                fi
                if [[ "$RECOVERY_TEST_SCENARIO" == readiness-recovery && "$check_count" -lt 3 ]]; then
                  exit 1
                fi
                exit 3
              fi

              secret=
              IFS= read -r secret || true
              if [[ "$secret" != recovery-fixture-secret ]]; then
                exit 1
              fi
              touch "$RECOVERY_TEST_ROOT/unlocked"
            '';
            recoverySleep = pkgs.writeShellScript "onepassword-recovery-test-sleep" ''
              set -euo pipefail
              printf '%s\n' "$1" >>"$RECOVERY_TEST_ROOT/sleeps"
            '';
            recoveryNotify = pkgs.writeShellScript "onepassword-recovery-test-notify" ''
              set -euo pipefail
              printf 'notified\n' >>"$RECOVERY_TEST_ROOT/notifications"
            '';
            recoveryTest = pkgs.writeShellScript "onepassword-keyring-recovery-test" ''
              set -euo pipefail

              production_script="$1"
              test_root="$TMPDIR/keyring-recovery"
              test_script="$test_root/unlock-test"
              mkdir -p "$test_root"

              ${pkgs.gnused}/bin/sed \
                -e 's|^op_bin=.*$|op_bin=${recoveryOp}|' \
                -e '/^if \[\[ -x \/run\/wrappers\/bin\/op \]\]; then$/,/^fi$/d' \
                -e 's|^keyring_helper=.*$|keyring_helper=${recoveryHelper}|' \
                -e 's|^sleep_bin=.*$|sleep_bin=${recoverySleep}|' \
                -e 's|^notify_bin=.*$|notify_bin=${recoveryNotify}|' \
                "$production_script" >"$test_script"
              chmod 700 "$test_script"

              run_case() {
                case_name="$1"
                expected_status="$2"
                case_root="$test_root/$case_name"
                mkdir -p "$case_root"
                export RECOVERY_TEST_ROOT="$case_root"
                export RECOVERY_TEST_SCENARIO="$case_name"

                set +e
                "$test_script" >"$case_root/stdout" 2>"$case_root/stderr"
                status=$?
                set -e
                test "$status" -eq "$expected_status"
              }

              mkdir -p "$test_root/already-unlocked"
              touch "$test_root/already-unlocked/unlocked"
              run_case already-unlocked 0
              test ! -e "$test_root/already-unlocked/op-count"
              test ! -e "$test_root/already-unlocked/sleeps"
              test ! -e "$test_root/already-unlocked/notifications"

              run_case readiness-recovery 0
              test "$(<"$test_root/readiness-recovery/op-count")" -eq 1
              printf '30\n2\n' >"$test_root/expected-readiness-sleeps"
              cmp \
                "$test_root/expected-readiness-sleeps" \
                "$test_root/readiness-recovery/sleeps"
              test ! -e "$test_root/readiness-recovery/notifications"

              deadline_script="$test_root/unlock-deadline-test"
              ${pkgs.gnused}/bin/sed \
                '/readiness_remaining=.*readiness_deadline - SECONDS/c\          readiness_remaining=0' \
                "$test_script" >"$deadline_script"
              chmod 700 "$deadline_script"
              export RECOVERY_TEST_ROOT="$test_root/deadline-rollover"
              export RECOVERY_TEST_SCENARIO=deadline-rollover
              mkdir -p "$RECOVERY_TEST_ROOT"
              set +e
              "$deadline_script" \
                >"$RECOVERY_TEST_ROOT/stdout" 2>"$RECOVERY_TEST_ROOT/stderr"
              deadline_status=$?
              set -e
              test "$deadline_status" -eq 1
              test "$(<"$RECOVERY_TEST_ROOT/check-count")" -eq 1
              test ! -e "$RECOVERY_TEST_ROOT/op-count"
              grep -Fxq 30 "$RECOVERY_TEST_ROOT/sleeps"
              test "$(wc -l <"$RECOVERY_TEST_ROOT/notifications")" -eq 1

              run_case third-success 0
              test "$(<"$test_root/third-success/op-count")" -eq 3
              printf '30\n120\n480\n' >"$test_root/expected-sleeps"
              cmp "$test_root/expected-sleeps" "$test_root/third-success/sleeps"
              test ! -e "$test_root/third-success/notifications"
              grep -Fq \
                'gnome-keyring-unlock: phase=complete attempt=3 result=unlocked' \
                "$test_root/third-success/stderr"

              run_case exhausted 1
              test "$(<"$test_root/exhausted/op-count")" -eq 3
              cmp "$test_root/expected-sleeps" "$test_root/exhausted/sleeps"
              test "$(wc -l <"$test_root/exhausted/notifications")" -eq 1
              grep -Fq \
                'gnome-keyring-unlock: phase=complete attempt=3 result=exhausted' \
                "$test_root/exhausted/stderr"

              if grep -R -Fq recovery-fixture-secret \
                "$test_root/already-unlocked/stdout" \
                "$test_root/already-unlocked/stderr" \
                "$test_root/readiness-recovery/stdout" \
                "$test_root/readiness-recovery/stderr" \
                "$test_root/deadline-rollover/stdout" \
                "$test_root/deadline-rollover/stderr" \
                "$test_root/third-success/stdout" \
                "$test_root/third-success/stderr" \
                "$test_root/exhausted/stdout" \
                "$test_root/exhausted/stderr" \
                "$test_root/third-success/sleeps" \
                "$test_root/exhausted/sleeps" \
                "$test_root/exhausted/notifications"; then
                exit 1
              fi
              ! grep -Fq 'systemctl' "$test_script"
              ! grep -Fq 'restart' "$test_script"
            '';
            testDbusDaemon = pkgs.writeShellScript "onepassword-test-dbus-daemon" ''
              args=()
              for arg in "$@"; do
                if [[ "$arg" != --session ]]; then
                  args+=("$arg")
                fi
              done
              exec ${pkgs.dbus}/bin/dbus-daemon \
                --config-file=${pkgs.dbus}/share/dbus-1/session.conf \
                "''${args[@]}"
            '';
          in
          pkgs.runCommand "check-onepassword-startup"
            {
              nativeBuildInputs = [
                pkgs.coreutils
                pkgs.dbus
                pkgs.gnugrep
              ];
            }
            ''
                  homeFiles=${self.homeConfigurations."jwilger@jwilger-t14".activationPackage}/home-files
                  hyprlandConfig="$homeFiles/.config/hypr/hyprland.lua"
                  onepasswordService="$homeFiles/.config/systemd/user/tenkr-onepassword.service"
                  onepasswordCliService="$homeFiles/.config/systemd/user/tenkr-onepassword-cli.service"
                  keyringService="$homeFiles/.config/systemd/user/tenkr-gnome-keyring-unlock.service"
                  keyringLaunchService="$homeFiles/.config/systemd/user/tenkr-gnome-keyring-unlock-launch.service"
                  keyringRetryService="$homeFiles/.config/systemd/user/tenkr-gnome-keyring-unlock-retry.service"
                  unlockScript="$(sed -n 's/^ExecStart=//p' "$keyringService")"
                  unlockHelper="$({ grep -oE '/nix/store/[a-z0-9]+-unlock-gnome-keyring-from-stdin-1/bin/unlock-gnome-keyring-from-stdin' "$unlockScript" || true; } | head -n 1)"
                  unlockSource="$(sed -n 's/^# Audited helper source: //p' "$unlockScript")"

                  test ! -e "$hyprlandConfig" || ! grep -Fq '1password --silent' "$hyprlandConfig"
                  test ! -e "$hyprlandConfig" || ! grep -Fq 'op read --no-newline' "$hyprlandConfig"
                  grep -Fq 'After=wayland-session-waitenv.service' "$onepasswordService"
                  ! grep -Eq '^After=([^[:space:]]+[[:space:]]+)*graphical-session\.target([[:space:]]|$)' "$onepasswordService"
                  grep -Fq '1password --silent' "$onepasswordService"
                  grep -Fq 'Wants=tenkr-onepassword.service' "$onepasswordCliService"
                  grep -Fq 'OP_SOCK=%t/onepassword/op-daemon.sock' "$onepasswordCliService"
                  grep -Fq 'onepassword-cli-daemon' "$onepasswordCliService"
                  grep -Fq 'Wants=tenkr-onepassword-cli.service' "$keyringService"
                  grep -Fq 'Wants=tenkr-onepassword.service' "$keyringService"
                  grep -Fq 'After=tenkr-onepassword-cli.service' "$keyringService"
                  grep -Fq 'After=tenkr-onepassword.service' "$keyringService"
                  grep -Fq 'PartOf=graphical-session.target' "$keyringService"
                  ! grep -Fq 'WantedBy=graphical-session.target' "$keyringService"
                  ! grep -Fq 'StartLimit' "$keyringService"
                  ! grep -Fq 'Restart=' "$keyringService"
                  grep -Fq 'LimitCORE=0' "$keyringService"
                  grep -Fq 'Wants=tenkr-onepassword.service' "$keyringLaunchService"
                  grep -Fq 'Wants=tenkr-onepassword-cli.service' "$keyringLaunchService"
                  grep -Fq 'After=tenkr-onepassword.service' "$keyringLaunchService"
                  grep -Fq 'After=tenkr-onepassword-cli.service' "$keyringLaunchService"
                  grep -Fq 'PartOf=graphical-session.target' "$keyringLaunchService"
                  grep -Fq 'WantedBy=graphical-session.target' "$keyringLaunchService"
                  grep -Fq 'Type=oneshot' "$keyringLaunchService"
                  grep -Fq 'RemainAfterExit=true' "$keyringLaunchService"
                  grep -Fq 'systemctl --user start --no-block tenkr-gnome-keyring-unlock.service' "$keyringLaunchService"
                  ! grep -Fq 'TimeoutStartSec=' "$keyringLaunchService"
                  grep -Fq 'systemctl --user start --no-block tenkr-gnome-keyring-unlock.service' "$keyringRetryService"
                  ! grep -Fq 'restart' "$keyringRetryService"
                  test -x "$unlockScript"
                  test -x "$unlockHelper"
                  test -f "$unlockSource"
                  grep -Fq 'read --no-newline' "$unlockScript"
                  grep -Fq -- "--account 'MRECLJED3JFMFCCB6ZS3D5AIZU'" "$unlockScript"
                  grep -Fq 'op://Personal/gqwzhhx32czatrq4wckuqzzo5q/password' "$unlockScript"
                  ! grep -Fq 'gnome-keyring-daemon' "$unlockScript"
                  grep -Fq 'ReadAlias' "$unlockSource"
                  grep -Fq 'UnlockWithMasterPassword' "$unlockSource"
                  grep -Fq 'Locked' "$unlockSource"
                  grep -Fq 'owner_is_current' "$unlockSource"
                  grep -Fq '#define MAX_PASSWORD_BYTES 4096' "$unlockSource"
                  grep -Fq 'STDIN_FILENO' "$unlockSource"
                  grep -Fq 'g_strcmp0 (session_algorithm, "plain") == 0' "$unlockSource"
                  ! grep -Eq '\b(getenv|fopen|open) *\(' "$unlockSource"
                  owner_check_count="$(grep -c 'owner_is_current (connection, owner' "$unlockSource")"
                  test "$owner_check_count" -eq 6

                  alias_line="$(grep -n 'collection = read_login_alias' "$unlockSource" | cut -d: -f1)"
                  alias_decision_line="$(grep -n 'strcmp (collection, "/")' "$unlockSource" | cut -d: -f1)"
                  alias_owner_line="$(awk -v start="$alias_line" -v end="$alias_decision_line" \
                    'NR > start && NR < end && /owner_is_current \(connection, owner/ { print NR; exit }' \
                    "$unlockSource")"
                  test -n "$alias_owner_line"

                  initial_locked_line="$(grep -n 'if (!read_locked' "$unlockSource" | head -n 1 | cut -d: -f1)"
                  initial_decision_line="$(grep -n 'if (!locked)' "$unlockSource" | head -n 1 | cut -d: -f1)"
                  initial_owner_line="$(awk -v start="$initial_locked_line" -v end="$initial_decision_line" \
                    'NR > start && NR < end && /owner_is_current \(connection, owner/ { print NR; exit }' \
                    "$unlockSource")"
                  test -n "$initial_owner_line"

                  unlock_line="$(grep -n '"UnlockWithMasterPassword"' "$unlockSource" | cut -d: -f1)"
                  final_locked_line="$(grep -n 'if (!read_locked' "$unlockSource" | tail -n 1 | cut -d: -f1)"
                  final_decision_line="$({ grep -n 'if (locked)' "$unlockSource" || true; } | tail -n 1 | cut -d: -f1)"
                  final_owner_line="$(awk -v start="$final_locked_line" -v end="$final_decision_line" \
                    'NR > start && NR < end && /owner_is_current \(connection, owner/ { print NR; exit }' \
                    "$unlockSource")"
                  test "$final_locked_line" -gt "$unlock_line"
                  test -n "$final_decision_line"
                  test -n "$final_owner_line"

                  dbus_call_timeout="$(sed -n 's/^# dbus_call_timeout=//p' "$unlockScript")"
                  readiness_timeout="$(sed -n 's/^readiness_timeout=//p' "$unlockScript")"
                  initial_settle="$(sed -n 's/^initial_settle=//p' "$unlockScript")"
                  approval_timeout="$(sed -n 's/^approval_timeout=//p' "$unlockScript")"
                  max_attempts="$(sed -n 's/^max_attempts=//p' "$unlockScript")"
                  post_read_dbus_calls="$(sed -n 's/^# post_read_dbus_calls=//p' "$unlockScript")"
                  kill_after="$(sed -n 's/^kill_after=//p' "$unlockScript")"
                  timeout_headroom="$(sed -n 's/^# timeout_headroom=//p' "$unlockScript")"
                  service_timeout="$(sed -n 's/^TimeoutStartSec=//p' "$keyringService")"
                  for timeout_value in \
                    "$dbus_call_timeout" "$readiness_timeout" "$approval_timeout" \
                    "$initial_settle" "$max_attempts" "$post_read_dbus_calls" \
                    "$kill_after" "$timeout_headroom" "$service_timeout"; do
                    test -n "$timeout_value"
                  done
                  expected_service_timeout=$((
                    initial_settle + 120 + 480
                    + max_attempts * (
                      readiness_timeout + approval_timeout
                      + post_read_dbus_calls * dbus_call_timeout + kill_after
                    )
                    + timeout_headroom
                  ))
                  test "$approval_timeout" -ge 120
                  test "$max_attempts" -eq 3
                  grep -Fq 'backoffs=(120 480)' "$unlockScript"
                  test "$service_timeout" -eq "$expected_service_timeout"

              ${pkgs.dbus}/bin/dbus-run-session \
                --dbus-daemon=${testDbusDaemon} \
                -- ${semanticTest} "$unlockHelper"

                  ${recoveryTest} "$unlockScript"

                  touch "$out"
            '';
        hyprland-catppuccin-borders = pkgs.runCommand "check-hyprland-catppuccin-borders" { } ''
          hyprlandConfig=${
            self.homeConfigurations."jwilger@jwilger-t14".activationPackage
          }/home-files/.config/hypr/hyprland.lua

          grep -Fq '["active_border"] = "rgb(cba6f7)"' "$hyprlandConfig"
          grep -Fq '["inactive_border"] = "rgb(1e1e2e)"' "$hyprlandConfig"
          grep -Fq '["border_active"] = "rgb(fab387)"' "$hyprlandConfig"
          grep -Fq '["border_inactive"] = "rgb(1e1e2e)"' "$hyprlandConfig"
          grep -Fq '["border_locked_active"] = "rgb(f38ba8)"' "$hyprlandConfig"
          grep -Fq '["border_locked_inactive"] = "rgb(1e1e2e)"' "$hyprlandConfig"

          touch "$out"
        '';
        interface =
          assert self.homeModules.default == self.homeModules.jwilger;
          pkgs.emptyDirectory;
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
