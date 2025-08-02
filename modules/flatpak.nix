{ config, inputs, pkgs, lib, ... }: {
  services.flatpak.enable = true;
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };
  environment.systemPackages = with pkgs; [ ];
}
