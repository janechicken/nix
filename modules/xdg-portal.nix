{ pkgs, lib, ... }:

{
  xdg.portal = {
    enable = true;
    config.common.default = "gtk";
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  # xdg-desktop-portal-gtk starts via graphical-session.target, but
  # with startx + Awesome WM that target fires before DISPLAY is set.
  # Portal-gtk crashes with "cannot open display:" and never retries.
  # Fix: set DISPLAY explicitly and auto-restart on failure.
  systemd.user.services.xdg-desktop-portal-gtk = {
    serviceConfig = {
      Environment = "DISPLAY=:0";
      Restart = "on-failure";
      RestartSec = "3s";
    };
  };
}
