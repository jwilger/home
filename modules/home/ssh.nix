{ config, ... }:
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    settings = {
      "*" = {
        ForwardAgent = true;
        IdentityAgent =
          if config.jwilger.hostProfile == "jwilger-t14" then "~/.1password/agent.sock" else "SSH_AUTH_SOCK";
      };
    };
  };
}
