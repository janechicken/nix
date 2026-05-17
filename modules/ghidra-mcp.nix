{ config, pkgs, lib, ... }:

let
  ghidraVersion = pkgs.ghidra-bin.version;
  extName = "GhidraMCP-${lib.replaceStrings ["."] ["-"] "1.4"}.zip";
in
{
  home.packages = [ pkgs.ghidra-mcp ];

  home.file = {
    ".ghidra/.ghidra_${ghidraVersion}/Extensions/${extName}" = {
      source = "${pkgs.ghidra-mcp}/share/ghidra-mcp/${extName}";
    };
  };
}
