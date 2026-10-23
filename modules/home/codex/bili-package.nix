{ pkgs }:
pkgs.stdenvNoCC.mkDerivation rec {
  pname = "billion-context";
  version = "0.1.204";
  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/billion-context/-/billion-context-${version}.tgz";
    hash = "sha256-ftwWrlzk5e5oEw5wajEqm/QW1fDY4f3RuhZV+UXDLXU=";
  };
  nativeBuildInputs = [ pkgs.makeWrapper ];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/billion-context" "$out/bin"
    cp -r dist package.json LICENSE "$out/lib/billion-context/"
    makeWrapper ${pkgs.nodejs_24}/bin/node "$out/bin/bili" \
      --add-flags "$out/lib/billion-context/dist/index.js" \
      --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.nodejs_24 ]}
    makeWrapper ${pkgs.nodejs_24}/bin/node "$out/bin/bili-mcp" \
      --add-flags "$out/lib/billion-context/dist/mcp.js"
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    "$out/bin/bili" --version | grep -F '${version}'
    ${pkgs.nodejs_24}/bin/node --input-type=module -e \
      'import { DatabaseSync } from "node:sqlite"; new DatabaseSync(":memory:").close()'
  '';
  meta = {
    description = "Reversible conversation compression proxy for coding agents";
    homepage = "https://github.com/ranxianglei/billion-context";
    license = pkgs.lib.licenses.mit;
    mainProgram = "bili";
    platforms = [ "x86_64-linux" ];
  };
}
