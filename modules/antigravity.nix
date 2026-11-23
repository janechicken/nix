{
  pkgs,
  ...
}:

{
  # ===========================================================================
  # Google Antigravity
  #
  # - `pkgs.antigravity-ide` — the agent-first IDE (VS Code fork), built with
  #   nixpkgs' buildVscode. Unfree, binary redistribution.
  # - `pkgs.antigravity-acp` — Google's ACP server (`agy_acp_server`), the
  #   piece agent harnesses such as T3 Code spawn as a provider.
  #
  # Both ship x86_64-linux and aarch64-linux sources in nixpkgs, so no arch
  # gating is needed for jane-pc or yogabook. `nixpkgs.config.allowUnfree` is
  # already set in modules/core.nix / modules/desktop.nix.
  # ===========================================================================
  home.packages = [
    pkgs.antigravity-ide
    pkgs.antigravity-acp
  ];
}
