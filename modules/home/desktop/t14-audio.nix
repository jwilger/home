{ config, lib, ... }:
let
  rule = match: properties: {
    matches = [ match ];
    actions.update-props = properties;
  };
  prefer = match: priority: rule match { "priority.session" = priority; };
in
{
  config = lib.mkIf (config.jwilger.hostProfile == "jwilger-t14") {
    xdg.configFile."wireplumber/wireplumber.conf.d/60-t14-desk-audio.conf".text = builtins.toJSON {
      # Consulted after a manually saved profile, before the generic ACP choice.
      "device.profile.priority.rules" = [
        (rule {
          "device.api" = "alsa";
          "device.vendor.id" = "0x046d";
          "device.product.id" = "0x0ab7";
        } { priorities = [ "output:analog-stereo+input:analog-stereo" ]; })
      ];
      # Rank eligible endpoints, not the graph clock driver or app-specific streams.
      "monitor.alsa.rules" = [
        (prefer {
          "alsa.components" = "USB046d:0ab7";
          "media.class" = "Audio/Source";
          "device.profile.name" = "analog-stereo";
        } 2400)
        (prefer { "node.name" = "alsa_input.pci-0000_c4_00.6.HiFi__Mic1__source"; } 2300)
        (prefer {
          "alsa.components" = "USB05ac:1114";
          "media.class" = "Audio/Sink";
          "device.profile.name" = "analog-stereo";
        } 1250)
      ];
    };
  };
}
