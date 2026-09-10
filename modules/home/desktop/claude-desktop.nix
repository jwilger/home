{ lib, pkgs, ... }:
let
  claude-desktop = pkgs.stdenv.mkDerivation rec {
    pname = "claude-desktop";
    version = "1.40609.1";

    src = pkgs.fetchurl {
      url = "https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop/claude-desktop_${version}_amd64.deb";
      hash = "sha256-gBguhRHGu+5t4mx+4iX70qmroidO8UBaHYnNj+ejgNw=";
    };

    nativeBuildInputs = with pkgs; [
      autoPatchelfHook
      binutils
      gnutar
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
      libcap_ng
      libseccomp
      libsecret
      libxkbcommon
      libx11
      libxcb
      libxcomposite
      libxdamage
      libxext
      libxfixes
      libxrandr
      libxtst
      mesa
      nspr
      nss
      pango
      systemd
      util-linux
    ];

    runtimeDependencies = with pkgs; [
      libGL
      libva
      pipewire
      wayland
    ];

    unpackPhase = ''
      runHook preUnpack
      ar x "$src"
      tar --no-same-permissions -xf data.tar.*
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/bin" "$out/lib" "$out/share"
      cp -r usr/lib/claude-desktop "$out/lib/"
      cp -r usr/share/* "$out/share/"

      makeWrapper "$out/lib/claude-desktop/claude-desktop" "$out/bin/claude-desktop" \
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeDependencies}" \
        --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations}}"

      substituteInPlace "$out/share/applications/com.anthropic.Claude.desktop" \
        --replace-fail "Exec=claude-desktop" "Exec=$out/bin/claude-desktop"

      runHook postInstall
    '';

    meta = {
      description = "Claude desktop app by Anthropic";
      homepage = "https://claude.com/download";
      license = lib.licenses.unfree;
      mainProgram = "claude-desktop";
      platforms = [ "x86_64-linux" ];
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    };
  };
in
{
  home.packages = [ claude-desktop ];
}
