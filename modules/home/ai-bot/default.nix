{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.home) homeDirectory;
  aiBotConfigDir = "${config.xdg.configHome}/ai-bot";
  aiBotGitConfig = "${config.xdg.configHome}/git/config-ai-bot";
  aiBotGhConfigDir = "${config.xdg.configHome}/gh-ai-bot";
  aiBotSigningKey = "${homeDirectory}/.ssh/ai-bot/signing_ed25519";
  aiBotSigningPubkey = "${aiBotSigningKey}.pub";
  aiBotAuthKey = "${homeDirectory}/.ssh/ai-bot/auth_ed25519";
  aiBotSshConfig = "${homeDirectory}/.ssh/config-ai-bot";
  aiBotAllowedSigners = "${aiBotConfigDir}/allowed_signers";
  gitBin = lib.getExe pkgs.git;
  ghBin = lib.getExe pkgs.gh;
  sshBin = lib.getExe pkgs.openssh;
  sshKeygenBin = lib.getExe' pkgs.openssh "ssh-keygen";
in
{
  config = lib.mkIf (config.jwilger.hostProfile == "gregor") {
    xdg.configFile."ai-bot/README.md".text = ''
      # AI Bot Bootstrap

      Required local files:

      - `${aiBotAuthKey}`
      - `${aiBotAuthKey}.pub`
      - `${aiBotSigningKey}`
      - `${aiBotSigningPubkey}`

      Initial setup:

      1. Upload `${aiBotAuthKey}.pub` as the bot account's SSH authentication key.
      2. Upload `${aiBotSigningPubkey}` as the bot account's SSH signing key.
      3. Run `ai-bot-init-allowed-signers`.
      4. Run `AI_GIT_PROFILE=bot gh auth login --hostname github.com --git-protocol ssh`.
    '';

    xdg.configFile."git/config-ai-bot".text = ''
      [include]
        path = ${config.xdg.configHome}/git/config
      [user]
        email = ai-bot@johnwilger.com
        name = AI Bot
        signingKey = ${aiBotSigningKey}
        useConfigOnly = true
      [commit]
        gpgSign = true
      [tag]
        gpgSign = true
      [gpg]
        format = ssh
      [gpg "ssh"]
        allowedSignersFile = ${aiBotAllowedSigners}
        program = ${sshKeygenBin}
      [core]
        sshCommand = ${sshBin} -F ${aiBotSshConfig}
    '';

    home.file.".ssh/config-ai-bot".text = ''
      Host github.com
        HostName github.com
        IdentityAgent none
        IdentityFile ${aiBotAuthKey}
        IdentitiesOnly yes
        User git
    '';

    home.file.".local/bin/ai-bot-init-allowed-signers" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail

        pubkey="${aiBotSigningPubkey}"
        output="${aiBotAllowedSigners}"

        if [[ ! -f "$pubkey" ]]; then
          printf 'Missing %s\n' "$pubkey" >&2
          exit 1
        fi

        install -m 700 -d "${aiBotConfigDir}"
        printf 'ai-bot@johnwilger.com %s\n' "$(cat "$pubkey")" > "$output"
        chmod 600 "$output"
      '';
    };

    home.file.".local/bin/git" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail

        if [[ "''${AI_GIT_PROFILE:-}" != "bot" ]]; then
          exec ${gitBin} "$@"
        fi

        export GIT_CONFIG_GLOBAL="${aiBotGitConfig}"
        exec ${gitBin} "$@"
      '';
    };

    home.file.".local/bin/gh" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail

        if [[ "''${AI_GIT_PROFILE:-}" != "bot" ]]; then
          exec ${ghBin} "$@"
        fi

        export GH_CONFIG_DIR="${aiBotGhConfigDir}"
        export GIT_SSH_COMMAND="${sshBin} -F ${aiBotSshConfig}"

        exec ${ghBin} "$@"
      '';
    };

    home.file.".local/bin/ssh" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail

        if [[ "''${AI_GIT_PROFILE:-}" != "bot" ]]; then
          exec ${sshBin} "$@"
        fi

        exec ${sshBin} -F ${aiBotSshConfig} "$@"
      '';
    };

    home.file.".local/bin/codex-ai" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        exec env AI_GIT_PROFILE=bot codex "$@"
      '';
    };

    home.file.".local/bin/claude-ai" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        exec env AI_GIT_PROFILE=bot GITHUB_PAT="$BOT_GITHUB_PAT" claude "$@"
      '';
    };

    home.file.".local/bin/opencode-ai" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        exec env AI_GIT_PROFILE=bot opencode "$@"
      '';
    };
  };
}
