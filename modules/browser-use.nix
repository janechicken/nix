{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    uv
    playwright-driver
    browser-use
  ];

  home.sessionVariables = {
    PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
  };
}
