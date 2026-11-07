{ lib, pkgs, ... }:
let
  isX86_64Linux = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
  camset = pkgs.camset.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      (pkgs.writeText "camset-supported-controls.patch" ''
        --- a/camset/v4l2control.py
        +++ b/camset/v4l2control.py
        @@ -42,2 +42,8 @@
        -        capabilites = capread.stdout.split('\n')
        +        # Only enumerate control types supported by Camset's scalar widgets.
        +        capabilites = [
        +            line for line in capread.stdout.split('\n')
        +            if '0x' not in line or any(
        +                kind in line for kind in ('(int)', '(bool)', '(menu)')
        +            )
        +        ]
                 return capabilites
      '')
    ];
    postPatch = (old.postPatch or "") + ''
      substituteInPlace camset/cam_window.py \
        --replace-fail 'frame.tostring()' 'frame.tobytes()'
    '';
  });
  tiny4linux = pkgs.stdenv.mkDerivation rec {
    pname = "tiny4linux";
    version = "2.2.1";

    src = pkgs.fetchurl {
      url = "https://github.com/OpenFoxes/Tiny4Linux/releases/download/v${version}/tiny4linux-gui";
      hash = "sha256-6nAGjUq4bjQ3rwd4epQ1Ws7jxvBJC2lNpIDo80SdMx8=";
    };
    cli = pkgs.fetchurl {
      url = "https://github.com/OpenFoxes/Tiny4Linux/releases/download/v${version}/tiny4linux-cli";
      hash = "sha256-3rOUEHRJuZD388FNQBkvYyCQpoDsp/+/ab1EsPMBr5g=";
    };

    dontUnpack = true;
    nativeBuildInputs = with pkgs; [
      autoPatchelfHook
      makeWrapper
    ];
    buildInputs = [ pkgs.stdenv.cc.cc.lib ];

    installPhase = ''
      runHook preInstall
      install -Dm755 "$src" "$out/bin/tiny4linux-gui"
      install -Dm755 "$cli" "$out/bin/tiny4linux-cli"
      ln -s tiny4linux-cli "$out/bin/t4l"
      runHook postInstall
    '';

    # Iced loads its display and rendering backends at runtime.
    postFixup = ''
      wrapProgram "$out/bin/tiny4linux-gui" \
        --prefix LD_LIBRARY_PATH : "${
          lib.makeLibraryPath (
            with pkgs;
            [
              fontconfig
              libGL
              libxkbcommon
              vulkan-loader
              wayland
              libx11
              libxcursor
              libxi
              libxrandr
            ]
          )
        }"
    '';

    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      "$out/bin/tiny4linux-cli" --help > /dev/null
      "$out/bin/t4l" tracking --help > /dev/null
      runHook postInstallCheck
    '';

    meta = {
      description = "GUI and CLI controls for OBSBOT Tiny cameras";
      homepage = "https://github.com/OpenFoxes/Tiny4Linux";
      license = lib.licenses.eupl12;
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      platforms = [ "x86_64-linux" ];
      mainProgram = "tiny4linux-gui";
    };
  };
in
{
  home.packages = lib.optionals isX86_64Linux [
    tiny4linux
    camset
    pkgs.v4l-utils
  ];

  systemd.user.services.obsbot-tracking-resume = lib.mkIf isX86_64Linux {
    Unit = {
      Description = "Restore OBSBOT tracking when a video application opens the camera";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.python3}/bin/python3 ${./obsbot-tracking.py} --t4l ${tiny4linux}/bin/t4l";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  xdg.desktopEntries = lib.mkIf isX86_64Linux {
    tiny4linux-dashboard = {
      name = "Tiny4Linux";
      comment = "OBSBOT camera tracking controls";
      exec = "${tiny4linux}/bin/tiny4linux-gui";
      icon = "camera-web";
      categories = [ "Utility" ];
      terminal = false;
    };
    tiny4linux-widget = {
      name = "Tiny4Linux (Widget)";
      comment = "Compact OBSBOT camera tracking controls";
      exec = "${tiny4linux}/bin/tiny4linux-gui --start-as widget";
      icon = "camera-web";
      categories = [ "Utility" ];
      terminal = false;
    };
  };
}
