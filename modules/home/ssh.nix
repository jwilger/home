{ ... }:
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    settings = {
      "*" = {
        ForwardAgent = true;
        IdentityAgent = "SSH_AUTH_SOCK";
      };
    };
  };
}
