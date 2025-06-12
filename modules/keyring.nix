{ config, inputs, pkgs, lib, ... }: {
  environment.systemPackages = with pkgs; [ libsecret gnome-keyring ];

  programs.seahorse.enable = true;
  services.gnome.gnome-keyring.enable = true;
  security.pam.services = { login.enableGnomeKeyring = true; };
}
