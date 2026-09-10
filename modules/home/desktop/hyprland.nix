{
  config,
  lib,
  pkgs,
  ...
}:
let
  lua = lib.generators.mkLuaInline;
  lockScreen = "${config.home.homeDirectory}/.local/bin/lock-screen";
  bind = keys: action: {
    _args = [
      keys
      (lua action)
    ];
  };
  exec = keys: command: bind keys "hl.dsp.exec_cmd(${builtins.toJSON command})";
  workspaceRules = map (number: {
    _args = [
      (
        {
          workspace = builtins.toString number;
          layout = "scrolling";
        }
        // lib.optionalAttrs (config.jwilger.hostProfile == "gregor") {
          monitor = "DP-3";
          persistent = true;
        }
      )
    ];
  }) (lib.range 1 9);
  workspaceBinds = lib.concatMap (number: [
    (bind "SUPER + ${builtins.toString number}" ''hl.dsp.focus({ workspace = "${builtins.toString number}" })'')
    (bind "SUPER + SHIFT + ${builtins.toString number}" ''hl.dsp.window.move({ workspace = "${builtins.toString number}" })'')
  ]) (lib.range 1 9);
  noctaliaThemeSeed = pkgs.writeText "hyprland-noctalia-theme.lua" ''
    local function apply_theme()
      hl.config({
        general = {
          col = {
            active_border = "rgb(cba6f7)",
            inactive_border = "rgb(45475a)",
          },
        },
      })
    end
    return { apply_theme = apply_theme }
  '';
in
{
  wayland.windowManager.hyprland = {
    enable = true;
    configType = "lua";
    package = pkgs.hyprland;
    portalPackage = null;
    # UWSM owns the graphical session lifecycle. Home Manager's separate
    # hyprland-session target races UWSM during login and can stop the session.
    systemd.enable = false;

    settings = {
      config = {
        general = {
          border_size = 2;
          gaps_in = 4;
          gaps_out = 4;
          layout = "scrolling";
        };

        decoration = {
          rounding = 12;
          shadow = {
            enabled = true;
            range = 4;
            render_power = 3;
          };
          blur = {
            enabled = true;
            size = 3;
            passes = 2;
            vibrancy = 0.1696;
          };
        };

        input = {
          kb_layout = "us";
          follow_mouse = 1;
          natural_scroll = true;
          touchpad = {
            natural_scroll = true;
            tap_to_click = true;
          };
        };

        scrolling = {
          column_width = 0.5;
          explicit_column_widths = "0.333, 0.5, 0.667";
          focus_fit_method = 1;
          fullscreen_on_one_column = false;
          wrap_focus = false;
          wrap_swapcol = false;
        };

        animations.enabled = true;
        cursor = {
          default_monitor =
            if config.jwilger.hostProfile == "jwilger-t14" then
              "desc:Apple Computer Inc StudioDisplay"
            else
              "DP-3";
          no_hardware_cursors = 0;
        };
      };

      monitor =
        if config.jwilger.hostProfile == "jwilger-t14" then
          [
            {
              _args = [
                {
                  output = "eDP-1";
                  mode = "2880x1800@60";
                  position = "0x540";
                  scale = 2.0;
                }
              ];
            }
            {
              _args = [
                {
                  output = "desc:Apple Computer Inc StudioDisplay";
                  mode = "5120x2880@60";
                  position = "1440x0";
                  scale = 2.0;
                }
              ];
            }
          ]
        else
          [
            {
              _args = [
                {
                  output = "DP-3";
                  mode = "5120x2880@60";
                  position = "auto";
                  scale = 2.0;
                }
              ];
            }
            {
              _args = [
                {
                  output = "";
                  mode = "preferred";
                  position = "auto";
                  scale = "auto";
                }
              ];
            }
          ];

      workspace_rule = workspaceRules;

      layer_rule = [
        {
          _args = [
            {
              name = "noctalia-shell";
              match.namespace = "^noctalia.*";
              no_anim = true;
              blur = true;
              blur_popups = true;
              ignore_alpha = 0.5;
            }
          ];
        }
      ];

      window_rule = [
        {
          _args = [
            {
              name = "float-1password";
              match.class = "^1Password$";
              float = true;
            }
          ];
        }
        {
          _args = [
            {
              name = "float-picture-in-picture";
              match.title = "^Picture-in-Picture$";
              float = true;
            }
          ];
        }
        {
          _args = [
            {
              name = "float-zenity";
              match.class = "^(org\\.gnome\\.Zenity|zenity)$";
              float = true;
            }
          ];
        }
      ];

      env = map (pair: { _args = pair; }) [
        [
          "DISPLAY"
          ":0"
        ]
        [
          "QT_QPA_PLATFORM"
          "wayland"
        ]
        [
          "SDL_VIDEODRIVER"
          "wayland"
        ]
        [
          "XDG_CURRENT_DESKTOP"
          "Hyprland"
        ]
        [
          "XDG_SESSION_DESKTOP"
          "Hyprland"
        ]
        [
          "XDG_SESSION_TYPE"
          "wayland"
        ]
        [
          "XCURSOR_SIZE"
          "24"
        ]
        [
          "XCURSOR_THEME"
          "Vanilla-DMZ"
        ]
      ];

      bind = [
        (exec "SUPER + RETURN" "wezterm")
        (exec "SUPER + SPACE" "noctalia msg panel-toggle launcher")
        (exec "SUPER + E" "nautilus")
        (exec "SUPER + SHIFT + E" "noctalia msg panel-toggle session")
        (exec "SUPER + ESCAPE" lockScreen)
        (bind "SUPER + Q" "hl.dsp.window.close()")
        (bind "SUPER + F" ''hl.dsp.window.fullscreen({ mode = "maximized" })'')
        (bind "SUPER + SHIFT + F" ''hl.dsp.window.fullscreen({ mode = "fullscreen" })'')
        (bind "SUPER + C" ''hl.dsp.layout("fit active")'')
        (bind "SUPER + H" ''hl.dsp.layout("focus l")'')
        (bind "SUPER + J" ''hl.dsp.focus({ direction = "d" })'')
        (bind "SUPER + K" ''hl.dsp.focus({ direction = "u" })'')
        (bind "SUPER + L" ''hl.dsp.layout("focus r")'')
        (bind "SUPER + LEFT" ''hl.dsp.layout("focus l")'')
        (bind "SUPER + DOWN" ''hl.dsp.focus({ direction = "d" })'')
        (bind "SUPER + UP" ''hl.dsp.focus({ direction = "u" })'')
        (bind "SUPER + RIGHT" ''hl.dsp.layout("focus r")'')
        (bind "SUPER + SHIFT + H" ''hl.dsp.layout("swapcol l")'')
        (bind "SUPER + SHIFT + J" ''hl.dsp.window.move({ direction = "d" })'')
        (bind "SUPER + SHIFT + K" ''hl.dsp.window.move({ direction = "u" })'')
        (bind "SUPER + SHIFT + L" ''hl.dsp.layout("swapcol r")'')
        (bind "SUPER + SHIFT + LEFT" ''hl.dsp.layout("swapcol l")'')
        (bind "SUPER + SHIFT + DOWN" ''hl.dsp.window.move({ direction = "d" })'')
        (bind "SUPER + SHIFT + UP" ''hl.dsp.window.move({ direction = "u" })'')
        (bind "SUPER + SHIFT + RIGHT" ''hl.dsp.layout("swapcol r")'')
        (bind "SUPER + R" ''hl.dsp.layout("colresize +conf")'')
        (bind "SUPER + MINUS" ''hl.dsp.layout("colresize -0.1")'')
        (bind "SUPER + EQUAL" ''hl.dsp.layout("colresize +0.1")'')
        (bind "SUPER + SHIFT + MINUS" "hl.dsp.window.resize({ x = 0, y = -50, relative = true })")
        (bind "SUPER + SHIFT + EQUAL" "hl.dsp.window.resize({ x = 0, y = 50, relative = true })")
        (exec "PRINT" ''grim -g "$(slurp)" - | wl-copy'')
        (exec "SUPER + PRINT" "grim - | wl-copy")
        (exec "SUPER + SHIFT + PRINT" ''grim -g "$(slurp -d)" - | wl-copy'')
        (exec "XF86AudioRaiseVolume" "pamixer -i 5")
        (exec "XF86AudioLowerVolume" "pamixer -d 5")
        (exec "XF86AudioMute" "pamixer -t")
        (exec "SUPER + M" "pamixer --default-source -t")
        (exec "SUPER + N" "noctalia msg notification-clear-active")
        (exec "SUPER + SHIFT + N" "noctalia msg notification-dnd-toggle")
        (exec "XF86AudioPlay" "playerctl play-pause")
        (exec "XF86AudioNext" "playerctl next")
        (exec "XF86AudioPrev" "playerctl previous")
        (exec "XF86MonBrightnessUp" "brightnessctl set +5%")
        (exec "XF86MonBrightnessDown" "brightnessctl set 5%-")
        (exec "SUPER + D" "voice-dictation")
        (bind "SUPER + V" "hl.dsp.window.float()")
        (bind "SUPER + SHIFT + V" ''
          function()
                    local active = hl.get_active_window()
                    if active ~= nil and active.floating then
                      hl.dispatch(hl.dsp.focus({ window = "tiled" }))
                    else
                      hl.dispatch(hl.dsp.focus({ window = "floating" }))
                    end
                  end'')
        (bind "SUPER + BRACKETLEFT" ''hl.dsp.layout("movewindowto l")'')
        (bind "SUPER + BRACKETRIGHT" ''hl.dsp.layout("movewindowto r")'')
      ]
      ++ workspaceBinds;
    };

    extraConfig = ''
      -- Home Manager symlinks this config into the Nix store. Resolve writable
      -- theme modules from the user's config directory, not the symlink target.
      package.path = ${builtins.toJSON "${config.xdg.configHome}/hypr/?.lua;"} .. package.path
      local function apply_noctalia_theme()
        package.loaded["noctalia"] = nil
        require("noctalia").apply_theme()
      end
      -- Config values are committed after this file is evaluated, so apply the
      -- generated theme on the next event-loop tick instead of being reset to
      -- Hyprland's defaults at the end of a reload.
      noctalia_theme_timer = hl.timer(apply_noctalia_theme, { timeout = 1, type = "oneshot" })
    '';
  };

  # Seed a writable theme module. Noctalia replaces it in-place later; keeping
  # it outside the Nix store is required by Noctalia's template post-hook.
  home.activation.hyprlandNoctaliaThemeSeed = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.config/hypr"
    if [ ! -e "$HOME/.config/hypr/noctalia.lua" ]; then
      install -m 0644 ${noctaliaThemeSeed} "$HOME/.config/hypr/noctalia.lua"
    fi
  '';
}
