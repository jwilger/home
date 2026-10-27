# Agent application release refresh

## agent-app-updates — Refresh desktop packages and verify CLI releases

**Goal:** Install current upstream desktop releases while retaining already-current Codex and Claude Code releases, then deliver and activate the remote configuration.

**Files:** `modules/home/desktop/chatgpt.nix`, `modules/home/desktop/claude-desktop.nix`; retain CLI configuration unchanged if current.

**Interfaces:** Existing official Debian sources, Codex GitHub stable releases, Claude Code official release channels, and Home Manager activation for `jwilger@jwilger-t14`.

**First failing test:** Not applicable: third-party version/hash metadata only, with a recorded RED exemption. Existing package builds and configuration checks are the acceptance tests.

**Steps:**
1. Compare configured/installed versions with official release metadata and validate downloaded package identities and checksums.
2. Update only necessary desktop version/hash pairs; retain Codex 0.164.0 and, per explicit user choice, Claude Code 2.1.311 rather than downgrade to stable-channel 2.1.308.
3. Build the affected packages and T14 activation package, run the repository checks, and complete independent review.
4. Commit with rationale and push the reviewed changes without including unrelated local files.
5. Inspect/synchronize the tracked remote and activate its immutable revision; inspect installed versions and report limitations.

**Run:** `nix flake check --print-build-logs`; `nix build '.#homeConfigurations."jwilger@jwilger-t14".activationPackage'`.

**Expected:** Both commands exit 0; remote contains the reviewed commit; Home Manager activation exits 0 and installed package versions match the verified targets.

**Out of scope:** Home Manager/nixpkgs upgrades, unrelated packages, npm extension audit remediation, CLI policy changes, GUI launches, and service restarts not required by activation.
