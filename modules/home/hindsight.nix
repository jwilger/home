{
  config,
  lib,
  pkgs,
  ...
}:
let
  homeDirectory = config.home.homeDirectory;
  hindsightDirectory = "${homeDirectory}/.hindsight";
  # Hooks must never depend on the vendor's delete-then-copy staging directory.
  codingAgentPackage = pkgs.stdenvNoCC.mkDerivation {
    pname = "hindsight-coding-agents";
    version = "0.8.1";
    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/@vectorize-io/hindsight-coding-agents/-/hindsight-coding-agents-0.8.1.tgz";
      hash = "sha256:407abd66ba5d4603a460ecfe6795d47a0e0687439a800d4bc79305f2ee2f5e1b";
    };
    dontBuild = true;
    postPatch = ''
      # Retain the surgical config merge, but use this immutable package directly.
      substituteInPlace dist/installer.js \
        --replace-fail 'function stageRuntime(c) {' 'function stageRuntime(c) { return c;' \
        --replace-fail 'cpSync2(src, dst, { recursive: true });' \
          'mkdirSync7(dst, { recursive: true }); execFileSync8("chmod", ["-R", "u+w", dst]); execFileSync8("cp", ["-r", "--no-preserve=mode", src + "/.", dst]);'
    '';
    installPhase = ''
      mkdir -p "$out"
      cp -r . "$out/"
    '';
  };
  codingAgentRuntime = "${codingAgentPackage}/dist";
  installHindsight = pkgs.writeShellApplication {
    name = "install-hindsight";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
      pkgs.nodejs_22
    ];
    text = ''
      mkdir -p "$HOME/.local/state/hindsight"
      exec flock "$HOME/.local/state/hindsight/install.lock" \
        node ${codingAgentRuntime}/installer.js "$@"
    '';
  };
  credentialEnv = "${hindsightDirectory}/openai.env";
  daemonConfig = "${hindsightDirectory}/daemon.json";
  postgres = pkgs.postgresql_18.withPackages (extensions: [ extensions.pgvector ]);
  postgresDirectory = "${homeDirectory}/.local/share/hindsight/postgres";
  postgresSocket = "${postgresDirectory}/socket";
  postgresPort = "5436";
  startPostgres = pkgs.writeShellApplication {
    name = "start-hindsight-postgres";
    runtimeInputs = [
      postgres
      pkgs.coreutils
    ];
    text = ''
      data_dir=${lib.escapeShellArg "${postgresDirectory}/data"}
      socket_dir=${lib.escapeShellArg postgresSocket}
      mkdir -p "$data_dir" "$socket_dir"
      chmod 700 "$data_dir" "$socket_dir"
      if [[ ! -f "$data_dir/PG_VERSION" ]]; then
        initdb -D "$data_dir" --auth-local=trust --auth-host=reject --no-instructions
      fi
      exec postgres -D "$data_dir" -k "$socket_dir" -p ${postgresPort} \
        -c listen_addresses= -c unix_socket_permissions=0700
    '';
  };
  preparePostgres = pkgs.writeShellApplication {
    name = "prepare-hindsight-postgres";
    runtimeInputs = [
      postgres
      pkgs.coreutils
    ];
    text = ''
      socket_dir=${lib.escapeShellArg postgresSocket}
      for _ in {1..60}; do
        if pg_isready -h "$socket_dir" -p ${postgresPort} -d postgres -q; then
          break
        fi
        sleep 1
      done
      pg_isready -h "$socket_dir" -p ${postgresPort} -d postgres -q
      if [[ "$(psql -h "$socket_dir" -p ${postgresPort} -d postgres -Atqc \
        "SELECT 1 FROM pg_database WHERE datname = 'hindsight'")" != 1 ]]; then
        createdb -h "$socket_dir" -p ${postgresPort} hindsight
      fi
      psql -h "$socket_dir" -p ${postgresPort} -d hindsight \
        -v ON_ERROR_STOP=1 -c 'CREATE EXTENSION IF NOT EXISTS vector'
    '';
  };
  # Git's log.showSignature adds verification text to --format=%aI, which
  # Hindsight sends as an ISO timestamp. Confine the override to its hooks.
  mkHooksPatch =
    name: hooksFile:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [
        pkgs.coreutils
        pkgs.jq
      ];
      text = ''
        hooks_file=${hooksFile}
        if [[ ! -f "$hooks_file" ]]; then
          exit 0
        fi
        hooks_tmp="$(mktemp "$(dirname "$hooks_file")/.hindsight-hooks.XXXXXX")"
        trap 'rm -f -- "$hooks_tmp"' EXIT
        jq '
          walk(
            if type == "object" and .type == "command" and
               (.command? | type == "string") and
               (.command | test("(/coding-agents|hindsight-coding-agents-[^/]+)/dist/")) then
              .command |= (
                if startswith("env GIT_CONFIG_COUNT=1 ") then .
                else "env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=log.showSignature GIT_CONFIG_VALUE_0=false " + .
                end
              )
            else . end
          )
        ' "$hooks_file" > "$hooks_tmp"
        chmod --reference="$hooks_file" "$hooks_tmp"
        mv -- "$hooks_tmp" "$hooks_file"
      '';
    };
  patchCodexHooks = mkHooksPatch "patch-hindsight-codex-hooks" ''"$HOME/.codex/hooks.json"'';
  patchClaudeHooks = mkHooksPatch "patch-hindsight-claude-hooks" ''"$HOME/.claude/settings.json"'';
  # Claude Code uses its native installer, not Nix; the vendor installer calls
  # `claude mcp add`, so systemd units need its bin directory on PATH.
  claudeBinDirectory = "${homeDirectory}/.local/bin";
  installClaudeCode = pkgs.writeShellApplication {
    name = "install-hindsight-claude-code";
    runtimeInputs = [
      pkgs.nodejs_22
      pkgs.uv
    ];
    text = ''
      export PATH=${lib.escapeShellArg claudeBinDirectory}:"$PATH"
      if ! command -v claude > /dev/null; then
        echo "Claude Code CLI is not installed yet." >&2
        exit 1
      fi
      # The Home Manager file already selects the server. Passing --server
      # makes the vendor installer rewrite that read-only symlink.
      ${lib.getExe installHindsight} install claude-code
      ${lib.getExe patchClaudeHooks}
    '';
  };
  installCodex = pkgs.writeShellApplication {
    name = "install-hindsight-codex";
    runtimeInputs = [ pkgs.nodejs_22 ];
    text = ''
      codex_bin=${lib.escapeShellArg (lib.getExe config.programs.codex.package)}
      if [[ ! -x "$codex_bin" ]]; then
        echo "Codex CLI is not installed yet." >&2
        exit 1
      fi
      "$codex_bin" features enable hooks
      # The Home Manager file already selects the server. Passing --server
      # makes the vendor installer rewrite that read-only symlink.
      ${lib.getExe installHindsight} install codex
      ${lib.getExe patchCodexHooks}
    '';
  };
  launchDaemon = pkgs.writeShellApplication {
    name = "launch-hindsight-daemon";
    runtimeInputs = [
      pkgs.nodejs_22
      pkgs.uv
    ];
    text = ''
      # uv-managed Python wheels need these native libraries on NixOS.
      export LD_LIBRARY_PATH=${
        lib.makeLibraryPath [
          pkgs.stdenv.cc.cc.lib
          pkgs.zlib
          pkgs.zstd
          pkgs.lz4
          pkgs.openssl
          pkgs.krb5
          pkgs.xz
        ]
      }''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
      if [[ "$HINDSIGHT_API_LLM_API_KEY" == REPLACE_WITH_OPENAI_API_KEY ]]; then
        echo "Replace the Hindsight OpenAI API key placeholder in 1Password." >&2
        exit 3
      fi
      exec node ${lib.escapeShellArg "${codingAgentRuntime}/daemon-start.js"} --harness codex
    '';
  };
  startDaemon = pkgs.writeShellApplication {
    name = "start-hindsight-daemon";
    runtimeInputs = [
      pkgs.curl
      pkgs.nodejs_22
    ];
    text = ''
      if curl --fail --silent --max-time 3 http://127.0.0.1:9077/health > /dev/null; then
        exit 0
      fi
      if [[ ! -f ${lib.escapeShellArg "${codingAgentRuntime}/daemon-start.js"} ]]; then
        echo "Hindsight Codex runtime is not installed yet." >&2
        exit 1
      fi

      op_bin=${lib.escapeShellArg "${pkgs._1password-cli}/bin/op"}
      if [[ -x /run/wrappers/bin/op ]]; then
        op_bin=/run/wrappers/bin/op
      fi

      export HINDSIGHT_CONFIG=${lib.escapeShellArg daemonConfig}
      exec "$op_bin" run --account MRECLJED3JFMFCCB6ZS3D5AIZU \
        --env-file=${lib.escapeShellArg credentialEnv} -- \
        ${lib.getExe launchDaemon}
    '';
  };
  importCodex = pkgs.writeShellApplication {
    name = "import-hindsight-codex-history";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.git
      pkgs.jq
      pkgs.nodejs_22
      pkgs.ripgrep
    ];
    text = ''
      # Keep signature verification banners out of git log's ISO date output.
      export GIT_CONFIG_COUNT=1
      export GIT_CONFIG_KEY_0=log.showSignature
      export GIT_CONFIG_VALUE_0=false
      declare -A roots=()
      sessions_dir="$HOME/.codex/sessions"
      if [[ ! -d "$sessions_dir" ]]; then
        echo "No Codex session transcripts found." >&2
        exit 1
      fi

      while IFS= read -r -d "" transcript; do
        cwd="$(head -n 1 "$transcript" | jq -r 'select(.type == "session_meta") | .payload.cwd // empty')"
        if [[ -z "$cwd" ]]; then
          continue
        fi
        if [[ ! -d "$cwd" ]]; then
          echo "Skipping missing session directory: $cwd" >&2
          continue
        fi
        root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$cwd")"
        roots["$root"]=1
      done < <(rg --files -0 -g '*.jsonl' "$sessions_dir")

      if [[ "$#" -gt 0 && "$1" == --list-roots ]]; then
        printf '%s\n' "''${!roots[@]}" | sort
        exit 0
      fi

      curl --fail --silent --show-error --max-time 5 http://127.0.0.1:9077/health > /dev/null
      import_log="$(mktemp)"
      cleanup_import() {
        import_status=$?
        rm -f -- "$import_log"
        if ! ${lib.getExe patchCodexHooks} || ! ${lib.getExe config.jwilger.codex.reconcile}; then
          echo "Could not reconcile Hindsight Codex hooks after import." >&2
          import_status=1
        fi
        exit "$import_status"
      }
      trap cleanup_import EXIT
      for root in "''${!roots[@]}"; do
        echo "Importing Codex history for $root"
        if ! (
          cd "$root"
          ${lib.getExe installHindsight} install codex \
            --import-conversations
        ) 2>&1 | tee "$import_log"; then
          exit 1
        fi
        # The vendor installer catches deepen failures and otherwise exits 0.
        if rg -q 'conversation import did not finish|--import-conversations skipped|gitlog ingest failed' "$import_log"; then
          echo "Hindsight import was incomplete; the timer will retry." >&2
          exit 1
        fi
      done

      state_dir="$HOME/.local/state/hindsight"
      mkdir -p "$state_dir"
      touch "$state_dir/codex-history-imported-v2"
    '';
  };
  importClaudeCode = pkgs.writeShellApplication {
    name = "import-hindsight-claude-history";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.git
      pkgs.jq
      pkgs.nodejs_22
      pkgs.ripgrep
      pkgs.uv
    ];
    text = ''
      # Keep signature verification banners out of git log's ISO date output.
      export GIT_CONFIG_COUNT=1
      export GIT_CONFIG_KEY_0=log.showSignature
      export GIT_CONFIG_VALUE_0=false
      export PATH=${lib.escapeShellArg claudeBinDirectory}:"$PATH"
      declare -A roots=()
      projects_dir="$HOME/.claude/projects"
      if [[ ! -d "$projects_dir" ]]; then
        echo "No Claude Code session transcripts found." >&2
        exit 1
      fi

      while IFS= read -r -d "" transcript; do
        cwd="$(jq -r 'select(.cwd? | type == "string") | .cwd' "$transcript" 2>/dev/null | head -n 1 || true)"
        if [[ -z "$cwd" ]]; then
          continue
        fi
        if [[ ! -d "$cwd" ]]; then
          echo "Skipping missing session directory: $cwd" >&2
          continue
        fi
        # Skip scratch directories; banks are keyed by git project.
        if ! root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"; then
          continue
        fi
        case "$root" in
          /tmp/* | "''${TMPDIR:-/tmp}"/*) continue ;;
        esac
        roots["$root"]=1
      done < <(rg --files -0 --max-depth 2 -g '*.jsonl' "$projects_dir")

      if [[ "$#" -gt 0 && "$1" == --list-roots ]]; then
        printf '%s\n' "''${!roots[@]}" | sort
        exit 0
      fi

      curl --fail --silent --show-error --max-time 5 http://127.0.0.1:9077/health > /dev/null
      import_log="$(mktemp)"
      cleanup_import() {
        import_status=$?
        rm -f -- "$import_log"
        if ! ${lib.getExe patchClaudeHooks}; then
          echo "Could not patch Hindsight Claude Code hooks after import." >&2
          import_status=1
        fi
        exit "$import_status"
      }
      trap cleanup_import EXIT
      for root in "''${!roots[@]}"; do
        echo "Importing Claude Code history for $root"
        if ! (
          cd "$root"
          ${lib.getExe installHindsight} install claude-code \
            --import-conversations
        ) 2>&1 | tee "$import_log"; then
          exit 1
        fi
        # The vendor installer catches deepen failures and otherwise exits 0.
        if rg -q 'conversation import did not finish|--import-conversations skipped|gitlog ingest failed' "$import_log"; then
          echo "Hindsight import was incomplete; the timer will retry." >&2
          exit 1
        fi
      done

      state_dir="$HOME/.local/state/hindsight"
      mkdir -p "$state_dir"
      touch "$state_dir/claude-history-imported-v1"
    '';
  };
in
{
  # Switch hook/MCP paths with the generation, rather than waiting for a timer.
  home.activation.hindsightHooks = lib.hm.dag.entryAfter [ "linkGeneration" "codexDefaults" ] ''
    run ${lib.getExe installCodex}
    if [[ -x ${lib.escapeShellArg "${claudeBinDirectory}/claude"} ]]; then
      run ${lib.getExe installClaudeCode}
    fi
  '';

  home.file.".hindsight/coding-agent.json".text = builtins.toJSON {
    serverMode = "self-hosted";
    harness = "codex";
    apiUrl = "http://127.0.0.1:9077";
    bankIdTemplate = "coding-agent::{gitProject}";
    resolveWorktrees = true;
    optInOnly = false;
    retainSessions = true;
    autoReflect = true;
    gitIngest = "message";
    # Home Manager owns runtime updates; sessions must not replace live hooks.
    autoUpdate = false;
  };

  home.file.".hindsight/daemon.json".text = builtins.toJSON {
    serverMode = "daemon";
    apiPort = 9077;
  };

  # This file contains a reference, not the credential. `op run` resolves it
  # only for the daemon-start process and its child.
  home.file.".hindsight/openai.env".text = ''
    HINDSIGHT_API_LLM_PROVIDER=openai
    HINDSIGHT_API_LLM_API_KEY="op://Personal/Hindsight/OpenAI API key"
    HINDSIGHT_API_EMBEDDINGS_PROVIDER=openai
    HINDSIGHT_API_EMBEDDINGS_OPENAI_API_KEY="op://Personal/Hindsight/OpenAI API key"
    HINDSIGHT_API_RERANKER_PROVIDER=rrf
    HINDSIGHT_EMBED_API_DATABASE_URL="postgresql://${config.home.username}@/hindsight?host=${postgresSocket}&port=${postgresPort}"
  '';

  systemd.user.services = {
    hindsight-postgres = {
      Unit.Description = "User-owned PostgreSQL with pgvector for Hindsight";
      Service = {
        Type = "exec";
        ExecStart = lib.getExe startPostgres;
        ExecStartPost = lib.getExe preparePostgres;
        Restart = "on-failure";
        RestartSec = "10s";
        TimeoutStartSec = "2min";
        LimitCORE = 0;
      };
      Install.WantedBy = [ "default.target" ];
    };
    hindsight-codex-install = {
      Unit = {
        Description = "Install and reconcile Hindsight Codex hooks and MCP";
      };
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe installCodex;
        ExecStartPost = lib.getExe config.jwilger.codex.reconcile;
        TimeoutStartSec = "10min";
        Restart = "on-failure";
        RestartSec = "30min";
      };
    };
    hindsight-claude-install = {
      Unit = {
        Description = "Install Hindsight Claude Code hooks, MCP and skill";
      };
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe installClaudeCode;
        TimeoutStartSec = "10min";
        Restart = "on-failure";
        RestartSec = "30min";
      };
    };

    hindsight-daemon-start = {
      Unit = {
        Description = "Start the local Hindsight memory daemon";
        Wants = [
          "hindsight-postgres.service"
          "tenkr-onepassword.service"
          "tenkr-onepassword-cli.service"
        ];
        After = [
          "hindsight-postgres.service"
          "hindsight-codex-install.service"
          "hindsight-claude-install.service"
          "tenkr-onepassword.service"
          "tenkr-onepassword-cli.service"
        ];
      };
      Service = {
        Type = "oneshot";
        Environment = [
          "OP_BIOMETRIC_UNLOCK_ENABLED=true"
          "OP_SOCK=%t/onepassword/op-daemon.sock"
        ];
        ExecStart = lib.getExe startDaemon;
        # hindsight-embed deliberately detaches the API after startup.
        KillMode = "process";
        TimeoutStartSec = "15min";
        LimitCORE = 0;
      };
    };
    hindsight-codex-history-import = {
      Unit = {
        Description = "Import historical Codex sessions into Hindsight";
        After = [
          "hindsight-codex-install.service"
          "hindsight-daemon-start.service"
        ];
        ConditionPathExists = "!%h/.local/state/hindsight/codex-history-imported-v2";
      };
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe importCodex;
        TimeoutStartSec = "3h";
      };
    };
    hindsight-claude-history-import = {
      Unit = {
        Description = "Import historical Claude Code sessions into Hindsight";
        After = [
          "hindsight-claude-install.service"
          "hindsight-daemon-start.service"
          "hindsight-codex-history-import.service"
        ];
        ConditionPathExists = "!%h/.local/state/hindsight/claude-history-imported-v1";
      };
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe importClaudeCode;
        TimeoutStartSec = "3h";
      };
    };
  };

  systemd.user.timers = {
    hindsight-codex-install = {
      Unit.Description = "Reconcile Hindsight Codex hooks and MCP weekly";
      Timer = {
        OnStartupSec = "1min";
        OnCalendar = "weekly";
        Persistent = true;
        RandomizedDelaySec = "1d";
      };
      Install.WantedBy = [ "timers.target" ];
    };
    hindsight-claude-install = {
      Unit.Description = "Reconcile Hindsight Claude Code hooks and MCP weekly";
      Timer = {
        OnStartupSec = "1min";
        OnCalendar = "weekly";
        Persistent = true;
        RandomizedDelaySec = "1d";
      };
      Install.WantedBy = [ "timers.target" ];
    };
    hindsight-daemon-start = {
      Unit.Description = "Keep the local Hindsight daemon available";
      Timer = {
        OnStartupSec = "1min";
        OnUnitActiveSec = "5min";
        OnUnitInactiveSec = "5min";
      };
      Install.WantedBy = [ "timers.target" ];
    };
    hindsight-codex-history-import = {
      Unit.Description = "Import historical Codex sessions after Hindsight is ready";
      Timer = {
        OnStartupSec = "15min";
        OnUnitInactiveSec = "1h";
      };
      Install.WantedBy = [ "timers.target" ];
    };
    hindsight-claude-history-import = {
      Unit.Description = "Import historical Claude Code sessions after Hindsight is ready";
      Timer = {
        OnStartupSec = "15min";
        OnUnitInactiveSec = "1h";
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
