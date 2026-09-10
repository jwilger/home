{
  config,
  lib,
  pkgs,
  ...
}:
let
  isX86_64Linux = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
in
lib.mkIf isX86_64Linux {
  # Install Zoom
  home.packages = with pkgs; [
    zoom-us
  ];

  # Configure Zoom to DISABLE embedded browser for SSO/OAuth authentication
  # SSO and Google login require the REAL browser (like Firefox) to handle
  # authentication properly. The embedded browser fails with referrer policy
  # errors and can't complete OAuth flows correctly.
  #
  # Setting these to FALSE forces Zoom to use xdg-open to launch your actual
  # browser, which then uses the zoom:// protocol handler to redirect back.
  #
  # Note on screen sharing:
  # Screen sharing on Wayland requires:
  # - pipewire and wireplumber (configured at system level)
  # - xdg-desktop-portal-hyprland and xdg-desktop-portal-gtk
  # - Proper portal configuration (see modules/desktop/hyprland.nix)
  #
  # If screen sharing still doesn't work after rebuild:
  # 1. Check Zoom settings -> Share Screen -> Advanced -> Screen Capture Mode
  #    and ensure it's set to use PipeWire
  # 2. Try restarting Zoom completely
  # 3. As a last resort, consider using the Flatpak version of Zoom:
  #    flatpak install flathub us.zoom.Zoom
  xdg.configFile."zoomus.conf".text = ''
    embeddedBrowserForFacebookLogin=false
    embeddedBrowserForGoogleLogin=false
    embeddedBrowserForSSOLogin=false
    enableWaylandShare=true
  '';

  # Fix the desktop file to use the correct Zoom path instead of /usr/bin/zoom
  # This enables the zoom:// protocol handler to work for OAuth callbacks
  # Note: Must match the original "Zoom.desktop" filename (capital Z) to override it
  xdg.dataFile."applications/Zoom.desktop".text = ''
    [Desktop Entry]
    Name=Zoom Workplace
    Comment=Zoom Video Conference
    Exec=env QT_QPA_PLATFORM=wayland ${config.home.profileDirectory}/bin/zoom %U
    Icon=Zoom
    Terminal=false
    Type=Application
    Encoding=UTF-8
    Categories=Network;Application;
    StartupWMClass=zoom
    MimeType=x-scheme-handler/zoommtg;x-scheme-handler/zoomus;x-scheme-handler/tel;x-scheme-handler/callto;x-scheme-handler/zoomphonecall;x-scheme-handler/zoomphonesms;x-scheme-handler/zoomcontactcentercall;application/x-zoom
    X-KDE-Protocols=zoommtg;zoomus;tel;callto;zoomphonecall;zoomphonesms;zoomcontactcentercall;
  '';

  # Register Zoom as the handler for zoom protocol URLs.
  # NOTE: this only writes the [Default Applications] entry in mimeapps.list,
  # which is what `xdg-mime`/`xdg-open` consult. It is NOT enough on its own to
  # make the SSO callback work in Chrome (see the activation script below).
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/zoommtg" = "Zoom.desktop";
      "x-scheme-handler/zoomus" = "Zoom.desktop";
    };
  };

  # Regenerate ~/.local/share/applications/mimeinfo.cache so the zoom:// SSO
  # callback works in Chrome.
  #
  # Root cause of the "no applications to open the link" window:
  # Chrome routes the zoommtg:// redirect through the xdg-desktop-portal
  # OpenURI interface, not through xdg-open. The portal builds its launch /
  # app-chooser list from g_app_info_get_recommended_for_type() — i.e. the
  # "recommended" apps, which come from the mimeinfo.cache sitting NEXT TO the
  # .desktop file that wins resolution. Our handler override (Zoom.desktop) is
  # installed into ~/.local/share/applications via xdg.dataFile above, but
  # nothing (neither NixOS nor home-manager) ever generates a mimeinfo.cache in
  # that directory. Result: `gio mime x-scheme-handler/zoommtg` reports Zoom as
  # the *default* but with "No recommended applications", so the portal opens an
  # empty app chooser -> "no applications to open the link".
  #
  # Building mimeinfo.cache here makes Zoom appear as a Registered + Recommended
  # handler, which is exactly what the OpenURI portal needs. Runs after files are
  # linked so the Zoom.desktop symlink already exists.
  home.activation.zoomMimeinfoCache = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${pkgs.desktop-file-utils}/bin/update-desktop-database -q \
      "${config.xdg.dataHome}/applications" || true
  '';

  programs.zsh.shellAliases.zoom = "QT_QPA_PLATFORM=wayland ${config.home.profileDirectory}/bin/zoom";
}
