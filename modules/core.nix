{ config, inputs, pkgs, lib, ... }:
{
  environment.systemPackages = with pkgs; [
    nh
    unzip
    lsd
    wget
    fastfetch
    rage
    uutils-coreutils-noprefix
    bat
    btop
    killall
    wineWowPackages.stable    
    wineWowPackages.staging
    winetricks
    home-manager
    zenity
    gpg-tui
    appimage-run
    p7zip-rar
    qrrs
  ];

  services.gnome.gnome-keyring.enable = true;
  programs.seahorse.enable = true;
  boot.loader.grub.configurationLimit = 42;
  
  nixpkgs.config = { allowBroken = true; allowUnfree = true; };
}
