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
  pairedWorkspaces = config.jwilger.hostProfile == "jwilger-t14";
  control = keys: action: bind keys ''function() require("desktop-controls").${action} end'';
  workspaceRules = lib.concatMap (
    number:
    [
      {
        _args = [
          {
            workspace = builtins.toString number;
            layout = "scrolling";
            monitor = if pairedWorkspaces then "desc:Apple Computer Inc StudioDisplay" else "DP-3";
            persistent = true;
            default = number == 1;
          }
        ];
      }
    ]
    ++ lib.optional pairedWorkspaces {
      _args = [
        {
          workspace = builtins.toString (number + 10);
          default_name = "${builtins.toString number}-laptop";
          layout = "scrolling";
          monitor = "eDP-1";
          persistent = true;
          default = number == 1;
        }
      ];
    }
  ) (lib.range 1 9);
  workspaceBinds = lib.concatMap (number: [
    (control "SUPER + ${builtins.toString number}" "workspace(${builtins.toString number})")
    (control "SUPER + SHIFT + ${builtins.toString number}" "move_to_workspace(${builtins.toString number})")
  ]) (lib.range 1 9);
  noctaliaThemeSeed = pkgs.writeText "hyprland-noctalia-theme.lua" ''
    local primary = "rgb(cba6f7)"
    local surface = "rgb(1e1e2e)"
    local on_surface = "rgb(cdd6f4)"
    local secondary = "rgb(fab387)"
    local on_secondary = "rgb(11111b)"
    local error = "rgb(f38ba8)"
    local on_error = "rgb(11111b)"

    local function apply_theme()
      hl.config({
        general = {
          col = {
            active_border = primary,
            inactive_border = surface,
          },
        },
        group = {
          col = {
            border_active = secondary,
            border_inactive = surface,
            border_locked_active = error,
            border_locked_inactive = surface,
          },
          groupbar = {
            col = {
              active = secondary,
              inactive = surface,
              locked_active = error,
              locked_inactive = surface,
            },
            text_color = on_secondary,
            text_color_inactive = on_surface,
            text_color_locked_active = on_error,
            text_color_locked_inactive = on_surface,
          },
        },
      })
    end

    return {
      colors = {
        primary = primary,
        surface = surface,
        on_surface = on_surface,
        secondary = secondary,
        on_secondary = on_secondary,
        error = error,
        on_error = on_error,
      },
      apply_theme = apply_theme,
    }
  '';
in
{
  wayland.windowManager.hyprland = {
    enable = true;
    configType = "lua";
    # NixOS owns the compositor on the T14. Keeping it out of the Home Manager
    # profile ensures hyprctl and the running Hyprland always come from the
    # same package set.
    package = if config.jwilger.hostProfile == "jwilger-t14" then null else pkgs.hyprland;
    portalPackage = null;
    # UWSM owns the graphical session lifecycle. Home Manager's separate
    # hyprland-session target races UWSM during login and can stop the session.
    systemd.enable = false;

    settings = {
      config = {
        general = {
          border_size = 2;
          col = {
            active_border = "rgb(cba6f7)";
            inactive_border = "rgb(1e1e2e)";
          };
          gaps_in = 4;
          gaps_out = 4;
          layout = "scrolling";
        };

        misc = {
          background_color = "rgb(11111b)";
          disable_hyprland_logo = true;
        };

        group = {
          col = {
            border_active = "rgb(fab387)";
            border_inactive = "rgb(1e1e2e)";
            border_locked_active = "rgb(f38ba8)";
            border_locked_inactive = "rgb(1e1e2e)";
          };
          groupbar = {
            col = {
              active = "rgb(fab387)";
              inactive = "rgb(1e1e2e)";
              locked_active = "rgb(f38ba8)";
              locked_inactive = "rgb(1e1e2e)";
            };
            text_color = "rgb(11111b)";
            text_color_inactive = "rgb(cdd6f4)";
            text_color_locked_active = "rgb(11111b)";
            text_color_locked_inactive = "rgb(cdd6f4)";
          };
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
          follow_mouse = 0;
          natural_scroll = true;
          touchpad = {
            natural_scroll = true;
            tap_to_click = false;
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

        # Native directional moves at a layout edge reach the paired monitor.
        binds.window_direction_monitor_fallback = true;
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
        (control "SUPER + C" ''scrolling("fit active")'')
        (control "SUPER + H" ''focus("l")'')
        (control "SUPER + J" ''focus("d")'')
        (control "SUPER + K" ''focus("u")'')
        (control "SUPER + L" ''focus("r")'')
        (control "SUPER + LEFT" ''focus("l")'')
        (control "SUPER + DOWN" ''focus("d")'')
        (control "SUPER + UP" ''focus("u")'')
        (control "SUPER + RIGHT" ''focus("r")'')
        (control "SUPER + SHIFT + H" ''move("l")'')
        (control "SUPER + SHIFT + J" ''move("d")'')
        (control "SUPER + SHIFT + K" ''move("u")'')
        (control "SUPER + SHIFT + L" ''move("r")'')
        (control "SUPER + SHIFT + LEFT" ''move("l")'')
        (control "SUPER + SHIFT + DOWN" ''move("d")'')
        (control "SUPER + SHIFT + UP" ''move("u")'')
        (control "SUPER + SHIFT + RIGHT" ''move("r")'')
        (bind "SUPER + CTRL + H" ''hl.dsp.focus({ monitor = "l" })'')
        (bind "SUPER + CTRL + L" ''hl.dsp.focus({ monitor = "r" })'')
        (bind "SUPER + CTRL + LEFT" ''hl.dsp.focus({ monitor = "l" })'')
        (bind "SUPER + CTRL + RIGHT" ''hl.dsp.focus({ monitor = "r" })'')
        (control "SUPER + CTRL + SHIFT + H" ''move_to_monitor("l")'')
        (control "SUPER + CTRL + SHIFT + L" ''move_to_monitor("r")'')
        (control "SUPER + CTRL + SHIFT + LEFT" ''move_to_monitor("l")'')
        (control "SUPER + CTRL + SHIFT + RIGHT" ''move_to_monitor("r")'')
        (control "SUPER + R" ''scrolling("colresize +conf")'')
        (control "SUPER + MINUS" ''scrolling("colresize -0.1")'')
        (control "SUPER + EQUAL" ''scrolling("colresize +0.1")'')
        (bind "SUPER + SHIFT + MINUS" "hl.dsp.window.resize({ x = 0, y = -50, relative = true })")
        (bind "SUPER + SHIFT + EQUAL" "hl.dsp.window.resize({ x = 0, y = 50, relative = true })")
        (exec "PRINT" ''grim -g "$(slurp)" - | wl-copy'')
        (exec "SUPER + PRINT" "grim - | wl-copy")
        (exec "SUPER + SHIFT + PRINT" ''grim -g "$(slurp -d)" - | wl-copy'')
        (exec "XF86AudioRaiseVolume" "pamixer -i 5")
        (exec "XF86AudioLowerVolume" "pamixer -d 5")
        (exec "XF86AudioMute" "pamixer -t")
        (exec "XF86AudioMicMute" "pamixer --default-source -t")
        (exec "SUPER + M" "pamixer --default-source -t")
        (exec "SUPER + N" "noctalia msg notification-clear-active")
        (exec "SUPER + SHIFT + N" "noctalia msg notification-dnd-toggle")
        (exec "XF86AudioPlay" "playerctl play-pause")
        (exec "XF86AudioNext" "playerctl next")
        (exec "XF86AudioPrev" "playerctl previous")
        (exec "XF86MonBrightnessUp" "noctalia msg brightness-up")
        (exec "XF86MonBrightnessDown" "noctalia msg brightness-down")
        # Press Scroll Lock again to stop and transcribe.
        (exec "SCROLL_LOCK" "voxtype record toggle")
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
        (control "SUPER + BRACKETLEFT" ''move_to_monitor("l")'')
        (control "SUPER + BRACKETRIGHT" ''move_to_monitor("r")'')
      ]
      ++ workspaceBinds;
    };

    extraConfig = ''
      -- Resolve the writable Noctalia theme module before the compositor's
      -- first frame. The declarative colors above remain the safe fallback
      -- until Noctalia has written its current palette.
      package.path = ${builtins.toJSON "${config.xdg.configHome}/hypr/?.lua;"} .. package.path
      require("desktop-controls").setup(${lib.boolToString pairedWorkspaces})
      local noctalia_ok, noctalia_theme = pcall(require, "noctalia")
      if noctalia_ok then
        noctalia_theme.apply_theme()
      end

      -- Start Noctalia from the compositor so this works with both UWSM and
      -- direct Hyprland sessions; neither path has to wait for a session
      -- target after Hyprland is already displaying its default background.
      -- 1Password and the GNOME Keyring unlock are user services. Keeping
      -- them out of this hook lets the unlock service wait for the desktop
      -- app and its CLI integration to become ready.
      hl.on("hyprland.start", function()
        hl.exec_cmd("noctalia --daemon")
        hl.exec_cmd("systemctl --user start voxtype.service")
      end)
    '';
  };

  xdg.configFile."hypr/desktop-controls.lua".source = ./hyprland/desktop-controls.lua;

  # Seed a writable theme module. Noctalia replaces it in-place later; keeping
  # it outside the Nix store is required by Noctalia's template post-hook.
  home.activation.hyprlandNoctaliaThemeSeed = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.config/hypr"
    if [ ! -e "$HOME/.config/hypr/noctalia.lua" ]; then
      install -m 0644 ${noctaliaThemeSeed} "$HOME/.config/hypr/noctalia.lua"
    fi
  '';

}
