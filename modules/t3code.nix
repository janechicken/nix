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
  piPackage = lib.optional piEnabled config.programs.pi.coding-agent.finalPackage;
  t3codePkg = pkgs.t3code.override {
    enableCodex = true;
    enableConnect = true;
    enableGitHub = true;
    enableGit = true;
    enableResourceMonitor = true;
    extraRuntimePackages = piPackage;
  };
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
  # feeds the app's CPU/RAM panel.
  #
  # T3 Connect is on: `enableConnect` bakes upstream's public relay/Clerk
  # identifiers (relay.t3.codes, the Clerk publishable key and JWT template,
  # straight from upstream's `.env.example`) into the web/server/desktop
  # bundles, and the wrapper exports T3CODE_CLOUDFLARED_PATH for the relay
  # tunnel. `cloudflared` comes from nixpkgs (built with `buildGo127Module`),
  # so both hosts get it straight from `cache.nixos.org` (2026.10.7, above
  # upstream's 2026.10.3 minimum): a download, not a build.
  # ===========================================================================
  home.packages = [ t3codePkg ];

  # Headless T3 Code background daemon: starts as soon as the user logs in
  # (WantedBy=default.target, independent of Hyprland/Wayland) so T3 Connect
  # stays reachable from phone/remote even without a desktop session or if the
  # compositor crashes. `t3code-desktop` attaches to the running server via
  # `~/.t3/userdata/server-owner.sqlite`.
  systemd.user.services.t3code = {
    Unit = {
      Description = "T3 Code server";
      After = [ "network-online.target" ];
      StartLimitIntervalSec = 300;
      StartLimitBurst = 5;
    };
    Service = {
      Type = "simple";
      WorkingDirectory = "%h";
      Environment = [
        "T3CODE_HOME=%h/.t3"
        "T3_BOOT_SERVICE_UNIT=t3code.service"
      ];
      ExecStart = "${t3codePkg}/bin/t3 serve";
      KillMode = "mixed";
      OOMPolicy = "continue";
      Restart = "always";
      RestartSec = 5;
      CPUWeight = 1000;
      IOWeight = 1000;
      MemoryLow = "1536M";
      OOMScoreAdjust = 100;
      ManagedOOMPreference = "avoid";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
