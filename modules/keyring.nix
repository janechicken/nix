{ config, inputs, pkgs, lib, ... }: {
  environment.systemPackages = with pkgs; [ libsecret gnome-keyring ];

  services.dbus.packages = [ pkgs.gnome-keyring pkgs.gcr ];
  programs.seahorse.enable = true;
  services.gnome.gnome-keyring.enable = true;
  security.pam.services = { login.enableGnomeKeyring = true; };
}
