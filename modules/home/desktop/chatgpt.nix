{ lib, pkgs, ... }:
let
  chatgpt = pkgs.stdenv.mkDerivation rec {
    pname = "chatgpt";
    version = "26.901.41600";

    src = pkgs.fetchurl {
      url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb";
      hash = "sha256-LKp98xTON+kEg1nY5qSnjiRXSjtU1r9RDxd1S2bdp3U=";
    };

    nativeBuildInputs = with pkgs; [
      asar
      autoPatchelfHook
      dpkg
      makeWrapper
    ];

    buildInputs = with pkgs; [
      alsa-lib
      at-spi2-atk
      at-spi2-core
      cairo
      cups
      dbus
      expat
      gdk-pixbuf
      glib
      gtk3
      libdrm
      libgbm
      libnotify
      libusb1
      libxkbcommon
      mesa
      nspr
      nss
      pango
      systemd
      libx11
      libxscrnsaver
      libxcomposite
      libxdamage
      libxext
      libxfixes
      libxrandr
      libxcb
    ];

    autoPatchelfIgnoreMissingDeps = [
      "libQt5Core.so.5"
      "libQt5Gui.so.5"
      "libQt5Widgets.so.5"
      "libQt6Core.so.6"
      "libQt6Gui.so.6"
      "libQt6Widgets.so.6"
      "libc.musl-x86_64.so.1"
    ];

    runtimeDependencies = with pkgs; [
      libGL
      libva
      pipewire
      stdenv.cc.cc.lib
      wayland
    ];

    unpackPhase = ''
      runHook preUnpack
      dpkg-deb -x "$src" .
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/bin" "$out/lib" "$out/share"
      cp -r usr/lib/chatgpt "$out/lib/"
      cp -r usr/share/* "$out/share/"

      asar extract "$out/lib/chatgpt/resources/app.asar" app
      substituteInPlace app/.vite/build/worker.js \
        --replace-fail 'async start(){if(this.disposed)return;if(this.logger.info(`Starting git repo watcher`),' \
        'async start(){return;if(this.disposed)return;if(this.logger.info(`Starting git repo watcher`),'
      asar pack app "$out/lib/chatgpt/resources/app.asar"

      makeWrapper "$out/lib/chatgpt/ChatGPT" "$out/bin/chatgpt" \
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeDependencies}" \
        --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations}}"

      substituteInPlace "$out/share/applications/chatgpt.desktop" \
        --replace-fail "Exec=chatgpt %U" "Exec=$out/bin/chatgpt %U"

      runHook postInstall
    '';

    meta = {
      description = "ChatGPT desktop app by OpenAI";
      homepage = "https://chatgpt.com/download/";
      license = lib.licenses.unfree;
      mainProgram = "chatgpt";
      platforms = [ "x86_64-linux" ];
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    };
  };
in
{
  home.packages = [ chatgpt ];
}
