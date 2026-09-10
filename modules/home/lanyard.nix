{
  config,
  jwilgerInputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.lanyard-ssh-agent;
  escapeSystemdExecArg =
    argument: lib.replaceStrings [ "%" "$" ] [ "%%" "$$" ] (builtins.toJSON (toString argument));
  escapeSystemdExecArgs = lib.concatMapStringsSep " " escapeSystemdExecArg;
  lanyardPackage = pkgs.rustPlatform.buildRustPackage {
    pname = "lanyard-ssh-agent";
    version = "0.1.2";
    src = jwilgerInputs.lanyard;
    cargoLock.lockFile = "${jwilgerInputs.lanyard}/Cargo.lock";
    nativeCheckInputs = [ pkgs.jq ];
  };
  stableSocket = "$XDG_RUNTIME_DIR/lanyard-ssh-agent/agent.sock";
  shellIntegration = ''
    _lanyard_incoming_agent="''${SSH_AUTH_SOCK-}"
    if [ -n "$_lanyard_incoming_agent" ] && [ -n "''${SSH_CONNECTION-}" ] && [ "$_lanyard_incoming_agent" != "${stableSocket}" ]; then
      "${cfg.package}/bin/lanyard-ssh-agent" register "$_lanyard_incoming_agent" >/dev/null 2>&1 || true
    fi
    export SSH_AUTH_SOCK="${stableSocket}"
    unset _lanyard_incoming_agent
  '';
in
{
  options.programs.lanyard-ssh-agent = {
    enable = lib.mkEnableOption "Lanyard SSH agent switching proxy";

    package = lib.mkOption {
      type = lib.types.package;
      default = lanyardPackage;
      defaultText = lib.literalExpression "pkgs.rustPlatform.buildRustPackage { ... }";
      description = "The Lanyard package to install.";
    };

    upstream = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.1password/agent.sock";
      defaultText = lib.literalExpression ''"\${config.home.homeDirectory}/.1password/agent.sock"'';
      example = "/run/user/1000/onepassword/agent.sock";
      description = "The durable local SSH agent socket used as Lanyard's final fallback.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    programs.bash.profileExtra = lib.mkIf pkgs.stdenv.hostPlatform.isLinux (
      lib.mkOrder 900 shellIntegration
    );
    programs.zsh.envExtra = lib.mkIf pkgs.stdenv.hostPlatform.isLinux (
      lib.mkOrder 900 shellIntegration
    );

    programs.ssh = {
      enable = true;
      enableDefaultConfig = lib.mkDefault false;
      settings."*".IdentityAgent = lib.mkDefault "SSH_AUTH_SOCK";
    };

    systemd.user.services.lanyard-ssh-agent = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      Install.WantedBy = [ "default.target" ];
      Unit.Description = "Lanyard SSH agent switching proxy";
      Service = {
        ExecStart = escapeSystemdExecArgs [
          "${cfg.package}/bin/lanyard-ssh-agent"
          "serve"
          "--upstream"
          cfg.upstream
        ];
        Restart = "on-failure";
      };
    };
  };
}
