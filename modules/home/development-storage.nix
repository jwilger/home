{
  config,
  lib,
  pkgs,
  ...
}:
let
  home = config.home.homeDirectory;
  projects = "${home}/projects";

  worktreeCleanup = pkgs.writeShellApplication {
    name = "cleanup-project-worktrees";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      git
    ];
    text = ''
      set -euo pipefail

      dry_run=false
      minimum_age_days="''${WORKTREE_CLEANUP_MINIMUM_AGE_DAYS:-7}"
      projects="''${PROJECTS_ROOT:-${projects}}"

      if [ "''${1:-}" = "--dry-run" ]; then
        dry_run=true
      elif [ "$#" -ne 0 ]; then
        echo "usage: cleanup-project-worktrees [--dry-run]" >&2
        exit 2
      fi

      case "$minimum_age_days" in
        *[!0-9]* | "")
          echo "WORKTREE_CLEANUP_MINIMUM_AGE_DAYS must be a non-negative integer" >&2
          exit 2
          ;;
      esac

      cutoff="$(( $(date +%s) - minimum_age_days * 86400 ))"

      in_use() {
        local candidate process_path resolved
        candidate="$1"
        for process_path in /proc/[0-9]*/cwd /proc/[0-9]*/fd/*; do
          resolved="$(readlink "$process_path" 2>/dev/null || true)"
          case "$resolved" in
            "$candidate" | "$candidate"/*)
              return 0
              ;;
          esac
        done
        return 1
      }

      declare -A repositories=()
      while IFS= read -r -d "" dot_git; do
        repository="''${dot_git%/.git}"
        common_dir="$(git -C "$repository" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
        [ -n "$common_dir" ] && repositories["$common_dir"]="$repository"
      done < <(
        find "$projects" \
          \( -type d \( \
            -name .cache -o \
            -name .direnv -o \
            -name node_modules -o \
            -name target -o \
            -name vendor \
          \) -prune \) -o \
          \( -name .git \( -type d -prune -o -type f \) -print0 \)
      )

      consider_worktree() {
        local base_ref branch_ref commit commit_time dirty head_tree locked nested_git path_hash preservation_branch slug status tree repository worktree
        repository="$1"
        base_ref="$2"
        worktree="$3"
        locked="$4"
        branch_ref="$5"

        if [ "$locked" = true ]; then
          echo "keep locked worktree: $worktree"
          return
        fi

        case "$worktree" in
          "$projects"/.worktrees/* | \
            "$projects"/.agent-worktrees/* | \
            "$projects"/*/.worktrees/* | \
            "$projects"/*/.agent-worktrees/*) ;;
          *)
            echo "keep worktree outside disposable directories: $worktree"
            return
            ;;
        esac

        if [ ! -d "$worktree" ]; then
          return
        fi
        commit_time="$(git -C "$worktree" log -1 --format=%ct)"
        if [ "$commit_time" -gt "$cutoff" ]; then
          echo "keep recent worktree: $worktree"
          return
        fi
        if in_use "$worktree"; then
          echo "keep in-use worktree: $worktree"
          return
        fi

        nested_git="$(find "$worktree" -mindepth 2 -name .git -print -quit)"
        if [ -n "$nested_git" ]; then
          echo "keep worktree containing nested Git state: $worktree"
          return
        fi

        slug="$(basename "$worktree" | tr -cs 'A-Za-z0-9._-' '-')"
        slug="''${slug%-}"
        path_hash="$(printf '%s' "$worktree" | sha256sum | cut -c1-10)"
        preservation_branch="wip/worktree/$slug-$path_hash-$(date +%Y%m%d%H%M%S)"
        if ! status="$(git -C "$worktree" status --porcelain --untracked-files=normal)"; then
          echo "keep worktree after status inspection failed: $worktree"
          return
        fi
        dirty=false
        [ -z "$status" ] || dirty=true

        if $dirty; then
          if $dry_run; then
            echo "would preserve dirty worktree on $preservation_branch: $worktree"
          else
            if ! git -C "$worktree" add --all \
              || ! tree="$(git -C "$worktree" write-tree)"; then
              echo "keep worktree after staging WIP state failed: $worktree"
              return
            fi
            head_tree="$(git -C "$worktree" rev-parse 'HEAD^{tree}')"
            if [ "$tree" = "$head_tree" ]; then
              echo "keep worktree whose dirty state cannot be captured: $worktree"
              return
            fi
            if ! commit="$(
              printf '%s\n\n%s\n' \
                "chore: preserve retired worktree state" \
                "Automatically captured before retiring $worktree." \
                | git -C "$worktree" commit-tree "$tree" -p HEAD
            )" || ! git --git-dir="$repository" branch "$preservation_branch" "$commit"; then
              echo "keep worktree after WIP commit creation failed: $worktree"
              return
            fi
            echo "preserved dirty worktree on $preservation_branch: $worktree"
          fi
        elif [ -z "$branch_ref" ] \
          && { [ -z "$base_ref" ] || ! git -C "$worktree" merge-base --is-ancestor HEAD "$base_ref"; }; then
          if $dry_run; then
            echo "would preserve detached worktree on $preservation_branch: $worktree"
          else
            if ! git --git-dir="$repository" branch "$preservation_branch" "$(git -C "$worktree" rev-parse HEAD)"; then
              echo "keep detached worktree after branch creation failed: $worktree"
              return
            fi
            echo "preserved detached worktree on $preservation_branch: $worktree"
          fi
        fi

        if $dry_run; then
          echo "would force-remove disposable worktree: $worktree"
        else
          echo "force-remove disposable worktree: $worktree"
          git --git-dir="$repository" worktree remove --force -- "$worktree"
        fi
      }

      for common_dir in "''${!repositories[@]}"; do
        repository="$common_dir"
        base_ref=""
        for candidate_ref in \
          refs/remotes/origin/main \
          refs/remotes/origin/master \
          refs/heads/main \
          refs/heads/master; do
          if git --git-dir="$repository" show-ref --verify --quiet "$candidate_ref"; then
            base_ref="$candidate_ref"
            break
          fi
        done

        first_worktree=true
        branch_ref=""
        worktree=""
        locked=false
        while IFS= read -r -d "" field; do
          if [ -z "$field" ]; then
            if $first_worktree; then
              first_worktree=false
            elif [ -n "$worktree" ]; then
              consider_worktree "$repository" "$base_ref" "$worktree" "$locked" "$branch_ref"
            fi
            branch_ref=""
            worktree=""
            locked=false
            continue
          fi

          case "$field" in
            "worktree "*) worktree="''${field#worktree }" ;;
            "branch "*) branch_ref="''${field#branch }" ;;
            locked | "locked "*) locked=true ;;
          esac
        done < <(git --git-dir="$repository" worktree list --porcelain -z)

        if ! $dry_run; then
          git --git-dir="$repository" worktree prune --expire now
        fi
      done
    '';
  };

  rustBuildCleanup = pkgs.writeShellApplication {
    name = "cleanup-rust-build-artifacts";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
    ];
    text = ''
      set -euo pipefail

      dry_run=false
      maximum_gib="''${RUST_BUILD_CACHE_MAX_GIB:-25}"
      minimum_age_days="''${RUST_BUILD_CACHE_MINIMUM_AGE_DAYS:-7}"
      projects="''${PROJECTS_ROOT:-${projects}}"
      legacy_target="''${LEGACY_CARGO_TARGET_DIR:-${home}/.build/cargo}"

      if [ "''${1:-}" = "--dry-run" ]; then
        dry_run=true
      elif [ "$#" -ne 0 ]; then
        echo "usage: cleanup-rust-build-artifacts [--dry-run]" >&2
        exit 2
      fi

      case "$maximum_gib:$minimum_age_days" in
        *[!0-9:]* | :* | *:)
          echo "Rust cache size and age limits must be non-negative integers" >&2
          exit 2
          ;;
      esac

      maximum_kib="$(( maximum_gib * 1024 * 1024 ))"
      cutoff="$(( $(date +%s) - minimum_age_days * 86400 ))"
      targets_file="$(mktemp)"
      trap 'rm -f "$targets_file"' EXIT

      in_use() {
        local candidate process_path project resolved
        candidate="$1"
        project="''${candidate%/target}"
        for process_path in /proc/[0-9]*/cwd /proc/[0-9]*/fd/*; do
          resolved="$(readlink "$process_path" 2>/dev/null || true)"
          case "$resolved" in
            "$candidate" | "$candidate"/* | "$project" | "$project"/*)
              return 0
              ;;
          esac
        done
        return 1
      }

      record_target() {
        local modified rustc_info_modified size target
        target="$1"
        [ -d "$target" ] || return
        size="$(du -sk --one-file-system "$target" | cut -f1)"
        modified="$(stat -c %Y "$target")"
        if [ -f "$target/.rustc_info.json" ]; then
          rustc_info_modified="$(stat -c %Y "$target/.rustc_info.json")"
          if [ "$rustc_info_modified" -gt "$modified" ]; then
            modified="$rustc_info_modified"
          fi
        fi
        printf '%s\t%s\t%s\0' "$modified" "$size" "$target" >> "$targets_file"
      }

      record_target "$legacy_target"
      while IFS= read -r -d "" target; do
        [ -f "''${target%/target}/Cargo.toml" ] && record_target "$target"
      done < <(
        find "$projects" \
          \( -type d \( \
            -name .cache -o \
            -name .direnv -o \
            -name .git -o \
            -name node_modules -o \
            -name vendor \
          \) -prune \) -o \
          \( -type d -name target -print0 -prune \)
      )

      total_kib=0
      while IFS=$'\t' read -r -d "" modified size target; do
        total_kib="$(( total_kib + size ))"
      done < "$targets_file"

      while IFS=$'\t' read -r -d "" modified size target; do
        if [ "$modified" -gt "$cutoff" ] && [ "$total_kib" -le "$maximum_kib" ]; then
          continue
        fi
        if in_use "$target"; then
          echo "keep in-use Rust target: $target"
          continue
        fi

        if $dry_run; then
          echo "would remove $(( size / 1024 )) MiB Rust target: $target"
        else
          echo "remove $(( size / 1024 )) MiB Rust target: $target"
          rm -rf --one-file-system -- "$target"
        fi
        total_kib="$(( total_kib - size ))"
      done < <(sort -z -n "$targets_file")

      echo "$(( total_kib / 1024 )) MiB of Rust build artifacts retained"
    '';
  };
in
{
  home.packages = [
    rustBuildCleanup
    worktreeCleanup
  ];

  systemd.user.services.cleanup-project-worktrees = {
    Unit.Description = "Remove old unlocked disposable project worktrees";
    Service = {
      ExecStart = lib.getExe worktreeCleanup;
      IOSchedulingClass = "idle";
      Nice = 19;
      Type = "oneshot";
    };
  };

  systemd.user.services.cleanup-rust-build-artifacts = {
    Unit.Description = "Bound workspace-local Rust build artifacts";
    Service = {
      ExecStart = lib.getExe rustBuildCleanup;
      IOSchedulingClass = "idle";
      Nice = 19;
      Type = "oneshot";
    };
  };

  systemd.user.timers.cleanup-project-worktrees = {
    Install.WantedBy = [ "timers.target" ];
    Timer = {
      OnCalendar = "weekly";
      Persistent = true;
      RandomizedDelaySec = "2h";
    };
  };

  systemd.user.timers.cleanup-rust-build-artifacts = {
    Install.WantedBy = [ "timers.target" ];
    Timer = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "2h";
    };
  };
}
