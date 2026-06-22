{
  lib,
  fetchurl,
  stdenv,
  python3,
  makeWrapper,
}:

stdenv.mkDerivation rec {
  pname = "ghidra-mcp";
  version = "5.14.1";

  extensionZip = fetchurl {
    url = "https://github.com/bethington/ghidra-mcp/releases/download/v${version}/GhidraMCP-${version}.zip";
    hash = "sha256-Q5Yy+c+3psJ6F5o3AXmohafiVuNrtBiSlgYN1Jw4bCs=";
  };

  bridgeScript = fetchurl {
    url = "https://github.com/bethington/ghidra-mcp/releases/download/v${version}/bridge_mcp_ghidra.py";
    hash = "sha256-t4bIjSfwARCOdiAkb95486qZIZ9JlkUuMK1dHEZC4F8=";
  };

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/ghidra-mcp

    cp ${extensionZip} $out/share/ghidra-mcp/GhidraMCP-${version}.zip
    cp ${bridgeScript} $out/share/ghidra-mcp/bridge_mcp_ghidra.py

    runHook postInstall
  '';

  postFixup = ''
    makeWrapper ${
      python3.withPackages (ps: [
        ps.mcp
        ps.requests
      ])
    }/bin/python3 $out/bin/ghidra-mcp \
      --add-flags "$out/share/ghidra-mcp/bridge_mcp_ghidra.py"
  '';

  meta = with lib; {
    description = "MCP Server for Ghidra reverse engineering tool";
    homepage = "https://github.com/bethington/ghidra-mcp";
    license = licenses.asl20;
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
