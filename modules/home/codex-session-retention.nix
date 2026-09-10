{ pkgs, ... }:
let
  retentionDays = 7;
  dryRun = false;
  codex = "/home/jwilger/.local/bin/codex";
  codexSessionPrune = pkgs.writeShellApplication {
    name = "codex-session-prune";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
    ];
    text = ''
      set -euo pipefail

      session_dir="$HOME/.codex/sessions"

      if [[ ! -x ${codex} ]]; then
        echo "Codex executable is unavailable at ${codex}; skipping cleanup." >&2
        exit 0
      fi

      if [[ ! -d "$session_dir" ]]; then
        exit 0
      fi

      while IFS= read -r -d $'\0' session_file; do
        # Codex session file names end with the session UUID. Use `codex delete`
        # rather than removing JSONL files directly so Codex's index is updated.
        base="$(basename "$session_file")"
        session_id="''${base:28:-6}"

        if [[ ! "$session_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
          echo "Ignoring unrecognized Codex session filename: $session_file" >&2
          continue
        fi

        # A prior deletion can remove a descendant session found in the initial
        # traversal, so do not treat its now-missing path as a failure.
        [[ -e "$session_file" ]] || continue

        if ${if dryRun then "true" else "false"}; then
          echo "Would delete Codex session: $session_file"
        else
          ${codex} delete --force "$session_id"
        fi
      done < <(
        find "$session_dir" -type f -name 'rollout-*.jsonl' ! -newermt '${toString retentionDays} days ago' -print0
      )
    '';
  };
in
{
  systemd.user.services = {
    codex-session-prune = {
      Unit = {
        Description = "Prune stale local Codex sessions";
        ConditionFileIsExecutable = codex;
      };
      Service = {
        ExecStart = "${codexSessionPrune}/bin/codex-session-prune";
        Type = "oneshot";
      };
    };
  };

  systemd.user.timers.codex-session-prune = {
    Unit.Description = "Daily local Codex session retention";
    Timer = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
