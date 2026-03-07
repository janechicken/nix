{ config, inputs, pkgs, lib, ... }:
{
  programs.librewolf = {
    enable = true;
    nativeMessagingHosts = [ pkgs.keepassxc ];
    policies = {
      SearchEngines = {
        Default = "Startpage";
      };
    };
    
    profiles.jane = {
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
        "xpinstall.signatures.required" = false;
      };
    };
  };

  xdg = {
    enable = true;
    mimeApps = {
      enable = true;
      defaultApplications = {
        "default-web-browser" = [ "librewolf.desktop" ];
        "text/html" = [ "librewolf.desktop" ];
        "x-scheme-handler/http" = [ "librewolf.desktop" ];
        "x-scheme-handler/https" = [ "librewolf.desktop" ];
        "x-scheme-handler/about" = [ "librewolf.desktop" ];
        "x-scheme-handler/unknown" = [ "librewolf.desktop" ];
      };
    };
  };

  home.packages = with pkgs; [
    brave
  ];
}
