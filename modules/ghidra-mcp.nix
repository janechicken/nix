{
  config,
  pkgs,
  lib,
  ...
}:

let
  ghidraVersion = pkgs.ghidra-bin.version;
  extName = "GhidraMCP-${pkgs.ghidra-mcp.version}.zip";
in
{
  home.packages = [ pkgs.ghidra-mcp ];

  home.file = {
    ".ghidra/.ghidra_${ghidraVersion}/Extensions/${extName}" = {
      source = "${pkgs.ghidra-mcp}/share/ghidra-mcp/${extName}";
    };
  };
}
