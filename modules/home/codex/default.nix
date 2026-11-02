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
  defaults = pkgs.writeText "codex-home-manager-defaults.json" (
    builtins.toJSON {
      lean_cli = true;
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
          apps = false;
          plugins = false;
          remote_plugin = false;
          recommended_plugins = false;
          memories = false;
        };
        apps._default.enabled = false;
        memories = {
          generate_memories = false;
          use_memories = false;
        };
        skills.bundled.enabled = false;
        mcp_servers = {
          bili = {
            command = "${bili}/bin/bili-mcp";
            env.BILI_MCP_PROXY = "http://127.0.0.1:8787";
            startup_timeout_sec = 120;
          };

        };
      };
      retired_features = [
        "code_mode"
        "code_mode_only"
      ];
      rtk_command = "${lib.getExe rtk} hook codex";
      codex_executable = lib.getExe codex;

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
      reconcile
    ];
    # The runtime and its installers write config.toml/hooks.json. Activation
    # owns selected values, rather than making either file a store symlink.
    home.activation.codexDefaults = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe reconcile}
    '';
  };
}
