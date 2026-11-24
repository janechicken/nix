{
  config,
  pkgs,
  lib,
  ...
}:

let
  # `pi` (pi-nix) is not a nixpkgs wrapper flag: T3 Code's pi provider spawns the
  # bare `pi` command (packages/provider-pi `binaryPath: "pi"`), so it has to be
  # on the desktop app's PATH. Putting it in the wrapper keeps the pi provider
  # working even when t3code-desktop is started without the home-manager session
  # PATH (systemd unit, rofi/`hyprctl dispatch exec`, desktop entry).
  piEnabled = config.programs.pi.coding-agent.enable or false;
  piPackage = lib.optional piEnabled config.programs.pi.coding-agent.package;
in
{
  # ===========================================================================
  # T3 Code — minimal web GUI / desktop shell for coding agents
  # (https://t3.codes, github:pingdotgg/t3code).
  #
  # Version: the packaging lives in pkgs/t3code/ (bumped to 0.1.11, the latest
  # upstream stable release) and overlays/t3code.nix replaces only `t3code`.
  # nixos-unstable is still on 0.1.8, and staying on the pinned nixpkgs means
  # linux-mahua / mesa-mahua keep their existing store paths (no rebuild).
  #
  # Wrapper PATH: codex + gh + git (nixpkgs defaults) plus pi. Codex is kept
  # even though the app currently has it disabled, so enabling the provider in
  # the UI needs no rebuild. Claude / OpenCode / Cursor / jj / glab are left off
  # — they are not used here.
  #
  # The resource monitor sidecar (Rust, built from source) stays enabled: it
  # feeds the app's CPU/RAM panel. T3 Connect's cloudflared is deliberately not
  # wired (nixpkgs' `T3CODE_CLOUDFLARED_PATH` patch): `cloudflared` is not on
  # cache.nixos.org for either host, so it would add an uncached Go build for a
  # relay feature that is not used here.
  # ===========================================================================
  home.packages = [
    (pkgs.t3code.override {
      enableCodex = true;
      enableGitHub = true;
      enableGit = true;
      enableResourceMonitor = true;
      extraRuntimePackages = piPackage;
    })
  ];
}
