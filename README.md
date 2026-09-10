# Shared Home Manager configuration

Public, reusable Home Manager configuration for John Wilger's Linux workstations.

The flake exports `homeModules.jwilger`, `homeModules.default`, and standalone
configurations for `jwilger@gregor` and `jwilger@jwilger-t14`. Consumers must
set `jwilger.hostProfile` and should pin this flake to an immutable commit.

```nix
home-manager.users.jwilger = {
  imports = [ inputs.jwilger-home.homeModules.jwilger ];
  jwilger.hostProfile = "gregor";
};
```

Run `just check`, or build either standalone profile with
`just build jwilger@gregor` and `just build jwilger@jwilger-t14`.

Noctalia starts from a repository-owned immutable baseline that activation
copies into writable user configuration. After intentional UI changes, run
`just capture-noctalia`; it copies only the reviewed allowlist back to the
repository and leaves the Git diff uncommitted for inspection. Generated state
and `plugins/github-feed/settings.json` are never captured.
