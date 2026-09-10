{ lib, pkgs, ... }:
{
  home.packages = [ pkgs.abduco ];

  programs.zsh.initContent = ''
    # Attach or create an abduco session named after the directory and command.
    aa() {
      if (( $# == 0 )); then
        print -u2 "usage: aa <command> [args...]"
        return 2
      fi

      local session_name="''${PWD:t}-''${1:t}"
      print -n "\033]0;$session_name - abduco\007"
      ${lib.getExe pkgs.abduco} -A "$session_name" "$@"
    }
  '';
}
