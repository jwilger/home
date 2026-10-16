{
  config,
  lib,
  pkgs,
  ...
}:
let
  codex = import ./package.nix { inherit pkgs; };
  bili = import ./bili-package.nix { inherit pkgs; };
  rtk = import ./rtk.nix { inherit pkgs; };
  python = pkgs.python312.withPackages (p: [
    p.tomlkit
    p.ruamel-yaml
  ]);
  serena = pkgs.writeShellApplication {
    name = "serena";
    runtimeInputs = [ pkgs.uv ];
    text = ''
      # UV installs a version-pinned runtime in its user cache. Native wheels
      # need these libraries on NixOS; project LSPs remain in project shells.
      export LD_LIBRARY_PATH=${
        lib.makeLibraryPath [
          pkgs.stdenv.cc.cc.lib
          pkgs.zlib
          pkgs.zstd
          pkgs.openssl
          pkgs.libffi
        ]
      }''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
      exec uv tool run --from serena-agent==1.7.0 --python ${pkgs.python312}/bin/python3 \
        --no-python-downloads serena "$@"
    '';
  };
  context7 = pkgs.writeShellApplication {
    name = "context7-codex-mcp";
    text = ''
      # MCP processes may inherit a reduced environment from the app-server.
      # Read the user-owned exports directly; never unlock 1Password at startup.
      if [[ -z "''${CONTEXT7_API_KEY:-}" && -f "$HOME/.envrc" ]]; then
        CONTEXT7_API_KEY="$(
          set +u
          # shellcheck source=/dev/null
          source "$HOME/.envrc" > /dev/null
          printf '%s' "''${CONTEXT7_API_KEY:-}"
        )"
      fi
      case "''${CONTEXT7_API_KEY:-}" in
        "" | REPLACE_WITH_* | op://*)
          echo "Set CONTEXT7_API_KEY in ~/.envrc before starting Context7." >&2
          exit 1
          ;;
      esac
      export CONTEXT7_API_KEY
      exec ${lib.getExe pkgs.context7-mcp}
    '';
  };
  defaults = pkgs.writeText "codex-home-manager-defaults.json" (
    builtins.toJSON {
      settings = {
        model = "gpt-6.1-sol";
        model_reasoning_effort = "low";
        plan_mode_reasoning_effort = "high";
        service_tier = "default";
        approvals_reviewer = "auto_review";
        sandbox_mode = "workspace-write";
        sandbox_workspace_write.network_access = true;
        web_search = "cached";
        model_verbosity = "low";
        tui.status_line = [
          "model-with-reasoning"
          "thread-name"
          "project-name"
          "run-state"
          "weekly-limit"
          "estimated-thread-cost"
          "fast-mode"
          "task-progress"
        ];
        tui.status_line_use_colors = true;
        features = {
          hooks = true;
          apps = true;
          remote_plugin = true;
        };
        apps._default.enabled = true;
        mcp_servers = {
          bili = {
            command = "${bili}/bin/bili-mcp";
            env.BILI_MCP_PROXY = "http://127.0.0.1:8787";
            startup_timeout_sec = 120;
          };
          serena = {
            command = lib.getExe serena;
            args = [
              "start-mcp-server"
              "--context"
              "codex"
              "--project-from-cwd"
              "--open-web-dashboard"
              "false"
              "--enable-gui-log-window"
              "false"
            ];
            startup_timeout_sec = 120;
          };
          context7 = {
            command = lib.getExe context7;
            env_vars = [ "CONTEXT7_API_KEY" ];
            startup_timeout_sec = 10;
          };
        };
      };
      retired_features = [
        "code_mode"
        "code_mode_only"
      ];
      rtk_command = "${lib.getExe rtk} hook codex";
      codex_executable = lib.getExe codex;
      serena_settings = {
        web_dashboard_open_on_launch = false;
        gui_log_window = false;
      };
      serena_trust = [ "${config.home.homeDirectory}/src/**" ];
    }
  );
  reconcile = pkgs.writeShellApplication {
    name = "reconcile-codex";
    text = ''
      exec ${python}/bin/python3 ${../../../scripts/reconcile-codex} \
        --home ${lib.escapeShellArg config.home.homeDirectory} --defaults ${defaults}
    '';
  };
in
{
  imports = [ ./bili.nix ];
  options.jwilger.codex.reconcile = lib.mkOption {
    type = lib.types.package;
    readOnly = true;
    description = "Reapply writable Codex defaults and compose managed hooks.";
  };
  config = {
    jwilger.codex.reconcile = reconcile;
    programs.codex = {
      enable = true;
      package = codex;
      context = ./AGENTS.md;
    };
    xdg.configFile."rtk/config.toml".text = ''
      [awareness]
      level = "default"
      [hooks]
      # Home Manager composes the native hook; RTK's installer heuristic
      # does not need to remind us to run its separate initializer.
      suppress_hook_warning = true
    '';
    home.packages = [
      rtk
      serena
      pkgs.context7-mcp
      context7
      reconcile
    ];
    # The runtime and its installers write config.toml/hooks.json. Activation
    # owns selected values, rather than making either file a store symlink.
    home.activation.codexDefaults = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe reconcile}
    '';
    systemd.user.services.serena-runtime-install = {
      Unit.Description = "Prepare the pinned Serena runtime";
      Service = {
        Type = "oneshot";
        ExecStart = "${lib.getExe serena} --help";
        TimeoutStartSec = "10min";
        Restart = "on-failure";
        RestartSec = "5min";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
