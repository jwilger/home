# Repair ChatGPT Local Work executor startup

## chatgpt-local-executor — Preserve writable private executor plugin copies

**Goal:** Fix the existing Local Work startup failure without changing desktop identity, chats, credentials, or CLI configuration.

**Evidence:** User reports the failure predates the release refresh. The user journal records `EACCES: permission denied, unlink '/home/jwilger/.config/ChatGPT/executor-plugins/codex-app-tools/.codex-plugin/plugin.json'` during Node `fs.cp`; the private destination directories are owned by the user but have mode 0555, and the manifest has mode 0444.

**Files:** `modules/home/desktop/chatgpt.nix`, narrowly scoped packaging helper/test files if needed, and this task record.

**Implementation:** Identify the executor plugin copy path; make only private destination copies owner-writable before overwrite and after copying, never following symlinks into immutable source trees. Retain fail-closed upstream patch matching and the existing separate plugin repair.

**First failing test:** Reproduce copying a Nix-store-like tree (0555 directories, 0444 manifest), including refreshing an existing read-only destination. Assert repaired copies remain writable and symlink targets are untouched.

**Run:** Focused regression tests; actual ChatGPT package build; `nix flake check --print-build-logs`; T14 activation-package build.

**Expected:** Reproduction fails before repair and passes after repair; builds/checks exit 0. Required independent review passes before delivery. Verify Local Work startup from journal evidence where possible; do not equate a package build with GUI acceptance.

**Runtime repair:** Limit any permission correction to the user-owned executor plugin copy using a non-symlink-following traversal. Do not delete user state or terminate/restart the GUI without permission.
