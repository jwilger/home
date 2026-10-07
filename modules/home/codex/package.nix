{ pkgs }:
pkgs.stdenvNoCC.mkDerivation rec {
  pname = "codex";
  version = "0.161.0";
  src = pkgs.fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-package-x86_64-unknown-linux-musl.tar.gz";
    hash = "sha256-BNirnby53w7fPGfcpQcqN0ur/fdiqbxK5kmuFAuOLPA=";
  };
  nativeBuildInputs = [
    pkgs.makeWrapper
    pkgs.autoPatchelfHook
    pkgs.python312
  ];
  # CLI/code-mode are musl binaries; the bundled voice runtime uses glibc.
  buildInputs = [
    pkgs.glibc
    pkgs.ncurses
  ];
  preFixup = ''
    addAutoPatchelfSearchPath "$out/lib/codex/codex-resources/voice/lib"
  '';
  dontUnpack = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/codex" "$out/bin"
    tar -xzf "$src" -C "$out/lib/codex"
    test -x "$out/lib/codex/bin/codex"
    test -x "$out/lib/codex/bin/codex-code-mode-host"
    makeWrapper "$out/lib/codex/bin/codex" "$out/bin/codex" \
      --prefix PATH : ${
        pkgs.lib.makeBinPath [
          pkgs.ripgrep
          pkgs.bubblewrap
        ]
      }
    ln -s ../lib/codex/bin/codex-code-mode-host "$out/bin/codex-code-mode-host"
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    # autoPatchelf registers fixup hooks, so refresh only after all fixups.
    python3 ${../../../scripts/fix-codex-manifests} "$out/lib/codex"
    python3 ${../../../scripts/fix-codex-manifests} "$out/lib/codex" --verify
    "$out/bin/codex" --version | grep -Fx 'codex-cli ${version}'
    LD_TRACE_LOADED_OBJECTS=1 "$out/lib/codex/codex-resources/voice/bin/codex-voice-host" > voice-libraries.log
    ! grep -F 'not found' voice-libraries.log
    "$out/lib/codex/codex-resources/zsh/bin/zsh" -c 'print codex-zsh-ready' | grep -Fx codex-zsh-ready
  '';
  meta = {
    description = "OpenAI Codex CLI with the official companion runtimes";
    homepage = "https://github.com/openai/codex";
    license = pkgs.lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "codex";
    sourceProvenance = [ pkgs.lib.sourceTypes.binaryNativeCode ];
  };
}
