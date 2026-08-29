{
  lib,
  python3,
  idapro,
  tomli-w,
  idaProMcpIdaDir ? null,
}:
# ida-pro-mcp — MCP bridge for IDA Pro (https://github.com/mrexodia/ida-pro-mcp).
# Two entry points:
#   ida-pro-mcp   — stdio proxy to a running IDA GUI (Edit → Plugins → MCP)
#   idalib-mcp    — headless supervisor over idalib; needs idalib activated
#                   (py-activate-idalib.py) or IDADIR set. IDA itself is NOT
#                   packaged here — it is proprietary, install it out-of-band.
python3.pkgs.buildPythonApplication {
  pname = "ida-pro-mcp";
  version = "1.4.0";
  pyproject = true;

  src = python3.pkgs.fetchPypi {
    pname = "ida_pro_mcp";
    version = "1.4.0";
    hash = "sha256-SXusxYx/R0hrCXB2ON2/LIbJ8DSmaMg7bk1f6Yv7AUY=";
  };

  # server.py resolves its own ida_mcp dir via __file__; runtime deps only.
  # idapro wheel is a 2 MB shim that loads the real idalib out of IDADIR at
  # runtime; it installs fine without IDA present.
  dependencies = [
    idapro
    tomli-w
    # wheel imports `mcp` but upstream pyproject omits it
    python3.pkgs.mcp
  ];
  build-system = [ python3.pkgs.setuptools ];

  # idalib-mcp spawns `sys.executable -m ida_pro_mcp.idalib_server` workers,
  # so the wrapper interpreter must be the one that has idapro installed.
  pythonImportsCheck = [ "ida_pro_mcp" ];

  # idalib loads libidalib.so out of the IDA install dir at import time.
  # Point this at the IDA install (or leave null and run py-activate-idalib.py
  # once yourself, which writes ~/.idapro/ida-config.json).
  postFixup = lib.optionalString (idaProMcpIdaDir != null) ''
    wrapProgram $out/bin/ida-pro-mcp --set IDADIR ${idaProMcpIdaDir}
    wrapProgram $out/bin/idalib-mcp --set IDADIR ${idaProMcpIdaDir}
  '';

  meta = {
    description = "MCP server for IDA Pro (vibe reversing)";
    homepage = "https://github.com/mrexodia/ida-pro-mcp";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
}
