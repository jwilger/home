{ pkgs }:
pkgs.stdenvNoCC.mkDerivation rec {
  pname = "rtk";
  version = "0.51.0";
  src = pkgs.fetchurl {
    url = "https://github.com/rtk-ai/rtk/releases/download/v${version}/rtk-x86_64-unknown-linux-musl.tar.gz";
    hash = "sha256-UCjTsZqPCZDTD+yfuwfjJ4K8VpjmGPsYYarYqcy6TrU=";
  };
  dontUnpack = true;
  installPhase = ''
    mkdir -p "$out/bin"
    tar -xzf "$src" -C "$out/bin"
    chmod +x "$out/bin/rtk"
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    "$out/bin/rtk" --version | grep -Fx 'rtk ${version}'
    "$out/bin/rtk" hook codex --help >/dev/null
  '';
  meta = {
    description = "Command output filtering with native Codex hooks";
    homepage = "https://github.com/rtk-ai/rtk";
    license = pkgs.lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "rtk";
    sourceProvenance = [ pkgs.lib.sourceTypes.binaryNativeCode ];
  };
}
