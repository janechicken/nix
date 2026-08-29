final: prev: {
  ida-pro = final.callPackage ../pkgs/ida-pro/default.nix {
    ida-pro-mcp = final.ida-pro-mcp;
  };
  ida-pro-mcp = final.callPackage ../pkgs/ida-pro-mcp/default.nix {
    idapro = final.python3.pkgs.idapro;
    tomli-w = final.python3.pkgs.tomli-w;
    idaProMcpIdaDir = null;
  };
}
