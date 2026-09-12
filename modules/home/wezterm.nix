{ config, lib, ... }:
{
  xdg.configFile."wezterm/wezterm.lua".force = true;

  programs.wezterm = {
    enable = true;

    settings =
      lib.optionalAttrs (config.jwilger.hostProfile == "jwilger-t14") {
        # WezTerm's mux otherwise captures the desktop session's SSH agent
        # (typically GNOME Keyring) and exposes it to panes through its own
        # /run/user/.../wezterm/agent.* socket. Point that proxy at 1Password on
        # the T14; Gregor selects its agent in the shell through Lanyard.
        default_ssh_auth_sock = "${config.home.homeDirectory}/.1password/agent.sock";
      }
      // {
        color_scheme = "Catppuccin Mocha";
        font = lib.generators.mkLuaInline ''
          wezterm.font_with_fallback({
            "JetBrainsMono Nerd Font Mono",
            "DejaVu Sans",
          })
        '';
        font_size = 11.0;
        window_background_opacity = 0.85;
        window_decorations = "NONE";
        window_padding = {
          bottom = 0;
          left = 0;
          right = 0;
          top = 0;
        };
        scrollback_lines = 10000;
        audible_bell = "Disabled";
        enable_tab_bar = true;
        hide_tab_bar_if_only_one_tab = true;
        use_fancy_tab_bar = false;
        tab_bar_at_bottom = false;
        colors = {
          tab_bar = {
            background = "#1e1e2e";
            active_tab = {
              bg_color = "#cba6f7";
              fg_color = "#1e1e2e";
            };
            inactive_tab = {
              bg_color = "#313244";
              fg_color = "#bac2de";
            };
          };
        };
      };

    extraConfig = ''
      return {
        keys = {
          {
            key = "Enter",
            mods = "SHIFT",
            action = wezterm.action.SendString("\n"),
          },
        },
      }
    '';
  };
}
