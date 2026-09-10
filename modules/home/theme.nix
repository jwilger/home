{ pkgs, ... }:
{
  catppuccin = {
    enable = true;
    autoEnable = false;
    helix.enable = false;
    starship.enable = false;
    flavor = "mocha";
    accent = "lavender";
  };

  # Keep the desktop cursor in the user profile. Hosts which consume this
  # Home Manager configuration should not need to duplicate cursor packages
  # and GTK/X11 settings at the system level.
  home.pointerCursor = {
    enable = true;
    package = pkgs.vanilla-dmz;
    name = "Vanilla-DMZ";
    size = 24;
    gtk.enable = true;
    x11.enable = true;
  };
}
