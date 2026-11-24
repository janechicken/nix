{
  config,
  inputs,
  pkgs,
  lib,
  ...
}:
{
  programs.librewolf = {
    enable = true;
    # `librewolf-bin` is NOT usable right now: its prebuilt tarball URL
    # (codeberg.org/api/packages/librewolf/generic/...) returns 404 for both
    # linux-x86_64 and linux-arm64. `pkgs.librewolf` is the from-source build and
    # is fully substituted from cache.nixos.org on both hosts — verified for
    # aarch64-linux (yogabook) and x86_64-linux (jane-pc), so nothing compiles
    # locally. If a nixpkgs bump ever lands before Hydra caches it, `nh home
    # build` on yogabook would start a multi-hour Firefox build: check the
    # dry-run first.
    package = pkgs.librewolf;
    nativeMessagingHosts = [ pkgs.keepassxc ];
    policies = {
      SearchEngines = {
        Default = "Startpage";
      };
    };

    profiles.jane = {
      search.force = true;
      extensions.packages = with inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system}; [
        keepassxc-browser
        darkreader
        sponsorblock
        fastforwardteam
        violentmonkey
        clearurls
        user-agent-string-switcher
        canvasblocker
      ];
      search.engines = {
        "Nix Packages" = {
          urls = [
            {
              template = "https://search.nixos.org/packages";
              params = [
                {
                  name = "type";
                  value = "packages";
                }
                {
                  name = "query";
                  value = "{searchTerms}";
                }
              ];
            }
          ];
          icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
          definedAliases = [ "@np" ];
        };
      };
      settings = {
        "privacy.resistFingerprinting" = false;
        "webgl.disabled" = false;
        "privacy.clearOnShutdown.downloads" = true;
        "privacy.clearOnShutdown.history" = false;
        "privacy.clearOnShutdown.cookies" = false;
        "privacy.sanitize.sanitizeOnShutdown" = false;
        "network.cookie.lifetimePolicy" = 0;
        "xpinstall.signatures.required" = false;
        # 0 = never draw tabs in titlebar -> no CSD -> no Firefox-drawn
        # min/max/close buttons. Awesome hides the server titlebar anyway.
        "browser.tabs.inTitlebar" = 0;
      };
    };
  };

  # Default browser is intentionally left non-declarative: no `xdg.mimeApps`
  # here (`xdg.mimeApps.enable` defaults to false, so no read-only
  # `mimeapps.list` is generated) — pick it once from the desktop's own chooser,
  # e.g. `xdg-settings set default-web-browser librewolf.desktop`.

  home.packages = with pkgs; [
    brave
  ];
}
