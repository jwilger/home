{
  config,
  lib,
  pkgs,
  ...
}:
let
  bili = import ./bili-package.nix { inherit pkgs; };
  origin = "http://127.0.0.1:8787";
  proxyConfig = pkgs.writeText "bili-codex.json" (
    builtins.toJSON {
      host = "127.0.0.1";
      port = 8787;
      autoUpdate = false;
      mitm.enabled = true;
      providers = { };
    }
  );
  ready = pkgs.writeShellScript "bili-ready" ''
    for attempt in $(${pkgs.coreutils}/bin/seq 1 60); do
      if ${pkgs.curl}/bin/curl --noproxy '*' --fail --silent --max-time 1 \
          ${origin}/__bili/health >/dev/null &&
          test -s ${lib.escapeShellArg "${config.xdg.dataHome}/billion-context/ca/combined-ca.pem"}; then
        exit 0
      fi
      sleep 1
    done
    echo 'bili failed to become ready' >&2
    exit 1
  '';
in
{
  home.packages = [ bili ];
  # Loaded by every normal Codex entry point, including the managed daemon
  # binary after updates. No wrapper, alternate CODEX_HOME, or --no-daemon.
  # Keep these scoped to Codex rather than exporting a session-wide proxy.
  home.file.".codex/.env".text = ''
    HTTPS_PROXY=${origin}
    HTTP_PROXY=${origin}
    # Bili rejects realtime voice WebSocket upgrades; model traffic uses chatgpt.com.
    NO_PROXY=localhost,127.0.0.1,::1,api.openai.com
    SSL_CERT_FILE=${config.xdg.dataHome}/billion-context/ca/combined-ca.pem
    BILI_MCP_PROXY=${origin}
  '';
  systemd.user.services.bili = {
    Unit.Description = "Persistent Billion Context proxy for the shared Codex daemon";
    Service = {
      ExecStart = "${lib.getExe bili} start --config ${proxyConfig} --no-auto-update";
      ExecStartPost = ready;
      Restart = "on-failure";
      RestartSec = 3;
      TimeoutStartSec = 75;
      UMask = "0077";
      Environment = [
        "XDG_DATA_HOME=${config.xdg.dataHome}"
        "XDG_STATE_HOME=${config.xdg.stateHome}"
        "XDG_CACHE_HOME=${config.xdg.cacheHome}"
      ];
      # Never let an inherited Codex proxy route bili back through itself.
      UnsetEnvironment = [
        "HTTP_PROXY"
        "HTTPS_PROXY"
        "ALL_PROXY"
        "http_proxy"
        "https_proxy"
        "all_proxy"
        "SSL_CERT_FILE"
        "BILI_CONFIG_FILE"
      ];
    };
    Install.WantedBy = [ "default.target" ];
  };
}
