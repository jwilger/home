{ pkgs }:
let
  alsaConfig = pkgs.writeText "codex-alsa.conf" ''
    <${pkgs.alsa-lib}/share/alsa/alsa.conf>
    # The bundled ALSA library cannot read NixOS's patched `libs` syntax.
    # Retain standard device definitions, but supply our own PipeWire defaults.
    !@hooks []
    pcm_type.!pipewire {
      lib ${pkgs.pipewire}/lib/alsa-lib/libasound_module_pcm_pipewire.so
    }
    ctl_type.!pipewire {
      lib ${pkgs.pipewire}/lib/alsa-lib/libasound_module_ctl_pipewire.so
    }
    pcm.!default {
      type pipewire
      playback_node "-1"
      capture_node "-1"
      hint { show on description "Default PipeWire Device" }
    }
    ctl.!default { type pipewire }
  '';
in
pkgs.stdenvNoCC.mkDerivation rec {
  pname = "codex";
  version = "0.163.0";
  src = pkgs.fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-package-x86_64-unknown-linux-musl.tar.gz";
    hash = "sha256-WCZGxr8FYesN5UD3/IW5EhsAkagmvG6Wgwt/FyISIYI=";
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
    mkdir -p "$out/lib/codex" "$out/bin" "$out/share/codex"
    ln -s ${alsaConfig} "$out/share/codex/alsa.conf"
    tar -xzf "$src" -C "$out/lib/codex"
    test -x "$out/lib/codex/bin/codex"
    test -x "$out/lib/codex/bin/codex-code-mode-host"
    # Codex filters ALSA variables out of its helper environment. Apply them
    # inside the helper launcher, after that boundary, rather than to all CLI children.
    wrapProgram "$out/lib/codex/codex-resources/voice/bin/codex-voice-host" \
      --set-default ALSA_CONFIG_PATH "$out/share/codex/alsa.conf" \
      --set-default ALSA_CONFIG_DIR ${pkgs.alsa-lib}/share/alsa
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
    LD_TRACE_LOADED_OBJECTS=1 "$out/lib/codex/codex-resources/voice/bin/.codex-voice-host-wrapped" > voice-libraries.log
    ! grep -F 'not found' voice-libraries.log
    # Exercise the bundled ALSA parser/plugin loader, even in builds without
    # audio devices or a PipeWire server. Device availability is checked live.
    python3 - "$out" <<'PY'
    import json
    import os
    import pathlib
    import select
    import struct
    import subprocess
    import sys

    helper = pathlib.Path(sys.argv[1]) / "lib/codex/codex-resources/voice/bin/codex-voice-host"
    # Reproduce the audio helper's filtered environment: no inherited ALSA settings.
    environment = {key: value for key, value in os.environ.items()
                   if not key.startswith("ALSA_")}
    commit = subprocess.check_output([helper, "--build-commit"], env=environment, text=True).strip()
    messages = [
        {"type": "hello", "protocol": 1, "buildCommit": commit},
        {"type": "listDevices", "kind": "input"},
        {"type": "listDevices", "kind": "output"},
        {"type": "close"},
    ]
    # The helper has a bounded control queue: await each reply before sending.
    with subprocess.Popen([helper], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, env=environment) as process:
        replies = []
        for message in messages:
            payload = json.dumps(message).encode()
            process.stdin.write(struct.pack(">I", len(payload)) + payload)
            process.stdin.flush()
            if not select.select([process.stdout], [], [], 20)[0]:
                process.kill()
                raise RuntimeError("voice helper reply timed out")
            header = process.stdout.read(4)
            if len(header) != 4:
                raise RuntimeError("voice helper closed before replying")
            size, = struct.unpack(">I", header)
            replies.append(json.loads(process.stdout.read(size)))
        process.stdin.close()
        process.wait(timeout=20)
        errors = process.stderr.read().decode(errors="replace")
        if process.returncode:
            raise RuntimeError(f"voice helper exited {process.returncode}: {errors}")
    for failure in ("Cannot access file", "Unknown field libs", "Cannot open shared library"):
        if failure in errors:
            raise RuntimeError(errors)
    if [reply["type"] for reply in replies] != ["ready", "deviceList", "deviceList", "closed"]:
        raise RuntimeError(f"unexpected voice helper replies: {replies}")
    print("Voice ALSA configuration and helper protocol verified")
    PY
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
