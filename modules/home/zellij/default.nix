{
  jwilgerInputs,
  lib,
  pkgs,
  ...
}:
let
  zjstatus = jwilgerInputs.zjstatus.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  home.packages = with pkgs; [
    zellij
  ];

  xdg.configFile."zellij/config.kdl".source = pkgs.replaceVars ./config.kdl {
    copy_command =
      if pkgs.stdenv.isDarwin then "/usr/bin/pbcopy" else lib.getExe' pkgs.wl-clipboard "wl-copy";
  };
  xdg.configFile."zellij/layouts/compact-with-datetime.kdl".source = pkgs.replaceVars ./layout.kdl {
    zjstatus_wasm = "file:${zjstatus}/bin/zjstatus.wasm";
  };
  # Zellij-specific shell aliases
  programs.zsh.shellAliases = {
    # Attach or create session named after current directory
    zz = ''
      local session_name="$(basename "$PWD")"
      print -n "\033]0;$session_name - Zellij\007"
      ${pkgs.zellij}/bin/zellij attach -c "$session_name"
    '';
  };
}
