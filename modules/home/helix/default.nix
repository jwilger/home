{ pkgs, lib, ... }:

{
  programs.helix = {
    enable = true;
    settings.theme = "catppuccin_mocha";
    # Keep defaults, but add language entries to wire formatters/LSPs with correct placeholders.
    settings = {
      editor = {
        text-width = 80;
        indent-guides = {
          render = true;
          character = "┊";
        };
        end-of-line-diagnostics = "hint";
        inline-diagnostics = {
          cursor-line = "warning";
        };
      };
      keys = {
        normal = {
          space = {
            q = {
              q = ":quit-all";
              Q = ":write-quit-all";
            };
            W = ":reflow";
            u = {
              w = ":toggle-option soft-wrap.enable";
            };
          };
          C-s = ":update";
          g = {
            a = "code_action";
          };
          tab = "move_parent_node_end";
          S-tab = "move_parent_node_start";
        };
        insert = {
          S-tab = "move_parent_node_start";
          C-s = [
            ":update"
            "normal_mode"
          ];
        };
        select = {
          tab = "extend_parent_node_end";
          S-tab = "extend_parent_node_start";
          C-s = [
            ":update"
            "normal_mode"
          ];
        };
      };
    };

    languages = {
      language = [
        {
          name = "markdown";
          soft-wrap.enable = true;
          formatter = {
            command = lib.getExe pkgs.prettier;
            args = [
              "--parser"
              "markdown"
              "--prose-wrap"
              "never"
            ];
            auto-format = true;
          };
        }
        {
          name = "markdown-rustdoc";
          formatter = {
            command = lib.getExe pkgs.prettier;
            args = [
              "--parser"
              "markdown"
              "--prose-wrap"
              "never"
            ];
            auto-format = true;
          };
        }
      ];
    };
  };

}
