{ config, inputs, pkgs, lib, ... }: {
  environment.systemPackages = with pkgs; [ libsecret gnome-keyring gcr_4 ];

  services.dbus.packages = [ pkgs.gnome-keyring pkgs.gcr_4 ];
  programs.seahorse.enable = true;
  services.gnome.gnome-keyring.enable = true;
  security.pam.services = { login.enableGnomeKeyring = true; };
}
