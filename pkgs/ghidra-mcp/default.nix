{ lib, fetchurl, stdenv, unzip, python3, makeWrapper }:

stdenv.mkDerivation rec {
  pname = "ghidra-mcp";
  version = "1.4";
  dashedVersion = lib.replaceStrings ["."] ["-"] version;

  src = fetchurl {
    url = "https://github.com/LaurieWired/GhidraMCP/releases/download/${version}/GhidraMCP-release-${dashedVersion}.zip";
    hash = "sha256-uBylJA/d5X6k6JkXDc2f3ubtKSRigMdCY6UJv8/H5zQ=";
  };

  sourceRoot = ".";

  nativeBuildInputs = [ unzip makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/ghidra-mcp

    cp GhidraMCP-release-${dashedVersion}/bridge_mcp_ghidra.py $out/share/ghidra-mcp/
    cp GhidraMCP-release-${dashedVersion}/GhidraMCP-${dashedVersion}.zip $out/share/ghidra-mcp/

    runHook postInstall
  '';

  postFixup = ''
    makeWrapper ${python3.withPackages (ps: [ ps.mcp ps.requests ])}/bin/python3 $out/bin/ghidra-mcp \
      --add-flags "$out/share/ghidra-mcp/bridge_mcp_ghidra.py"
  '';

  meta = with lib; {
    description = "MCP Server for Ghidra reverse engineering tool";
    homepage = "https://github.com/LaurieWired/GhidraMCP";
    license = licenses.asl20;
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
