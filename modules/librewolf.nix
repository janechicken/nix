{ config, inputs, pkgs, lib, ... }:

{
  programs.librewolf = {
    enable = true;
    nativeMessagingHosts = [ pkgs.keepassxc ];
    profiles.octo = {
      search = {
        force = true;
        default = "StartPage";
        order = [ "StartPage" "DuckDuckGo" "Google" ];
      };
      extensions.packages =
        with inputs.firefox-addons.packages."x86_64-linux"; [
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
          urls = [{
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
          }];
          icon =
            "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
          definedAliases = [ "@np" ];
        };
      };
      settings = {
        "privacy.resistFingerprinting" = false;
        "webgl.disabled" = false;
        "privacy.clearOnShutdown.downloads" = true;
        "privacy.clearOnShutdown.history" = false;
        "privacy.clearOnShutdown.cookies" = false;
        "network.cookie.lifetimePolicy" = 0;
        "browser.search.defaultenginename" = "StartPage";
        "browser.search.order.1" = "StartPage";
      };
    };
  };
}
