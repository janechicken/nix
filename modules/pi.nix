{
  pkgs,
  inputs,
  lib,
  ...
}:

let
  isX86 = pkgs.stdenv.hostPlatform.isx86_64;

  # The only extension wired in: the Refuseless provider
  # (api.refuseless.com, [OI]-compatible). Passed via --extension so pi loads
  # it from the repo tree; the API key comes from the environment
  # (REFUSELESS_API_KEY), never from a tracked file.
  refuselessExtension = ../dotfiles/pi/extensions/refuseless-provider.ts;

  # Sourced by the pi wrapper. The key is read from the sops-nix tmpfs only if
  # the secret is provisioned, so a host without it still launches pi (the
  # extension then registers its bundled seed models).
  #
  # One-time provisioning on a NixOS host:
  #   sops secrets/secrets.yaml          # add: refuseless_api_key: abl_...
  #   (plus sops.secrets."refuseless_api_key" in secrets/sops-nix.nix)
  piEnv = pkgs.writeText "pi-env.sh" ''
    if [ -r /run/secrets/refuseless_api_key ]; then
      REFUSELESS_API_KEY="$(cat /run/secrets/refuseless_api_key)"
      export REFUSELESS_API_KEY
    fi
  '';
in
{
  imports = [ inputs.pi-nix.homeManagerModules.default ];

  # ===========================================================================
  # pi coding agent (pi.dev)
  #
  # Package: pi.nix (github:lukasl-dev/pi.nix) — buildNpmPackage build with a
  #          Cachix binary cache (pi.cachix.org).
  # Config:  ~/.pi/agent (settings.json, mcp.json). Auth and other secrets stay
  #          in env vars fed by sops-nix; nothing secret is tracked here.
  # ===========================================================================

  programs.pi.coding-agent = {
    enable = true;

    # Appended to the system prompt via --append-system-prompt.
    rules = ''
      # Agent Identity

      Direct, precise coding assistant. No filler.

      # Hard Rules

      - Verify tool/subagent results before trusting them (stat, read output, run the test).
      - Unknown facts: look them up, never guess from training data.
      - Never emit a code block you have not read from the actual file.
      - This is NixOS: a missing system tool is `nix-shell -p <pkg>`, never apt/pip/npm.
    '';

    # ZERO local extensions besides refuseless; no remote extension packages.
    extensions = [ refuselessExtension ];

    settings = {
      defaultProvider = "refuseless";
      defaultModel = "deepseek-v4.1-flash-abliterated";
      hideThinkingBlock = true;
      compaction = {
        enabled = true;
        reserveTokens = 16384;
        keepRecentTokens = 20000;
      };
      retry = {
        enabled = true;
        maxRetries = 3;
      };
    };

    # Runtime env sourced by the wrapper (see piEnv above). A store-path string
    # is what the option's `path` type accepts; derivations are not paths.
    environment = "${piEnv}";
  };

  home.packages = lib.optionals isX86 [
    # IDA Pro wrapper; also exposes ida-pro-mcp / idalib-mcp with the IDA lib
    # environment, which the MCP entry below relies on.
    pkgs.ida-pro
  ];

  # IDA MCP bridge (x86_64 only; IDA is proprietary and not packaged).
  # idalib-mcp is the headless supervisor: call its set_target(path) tool to
  # open or switch a binary, auto-analysis runs on set_target.
  programs.pi.coding-agent.mcp = lib.mkIf isX86 {
    mcpServers.idalib-mcp = {
      command = "${pkgs.ida-pro}/bin/idalib-mcp";
      timeout = 1800000;
    };
  };

  # --- IDA MCP plugin (RPC server inside the IDA GUI, port 13337, x86_64 only)
  # `ida-pro-mcp --install` does this imperatively but also writes configs for
  # other tools (claude/cursor); do it declaratively instead. The python3.*
  # glob survives nixpkgs python bumps.
  home.activation.installIdaMcpPlugin = lib.mkIf isX86 (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p $HOME/.idapro/plugins
      ln -sfn ${pkgs.ida-pro-mcp}/lib/python3.*/site-packages/ida_pro_mcp/mcp-plugin.py $HOME/.idapro/plugins/mcp-plugin.py
    ''
  );
}
