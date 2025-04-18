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
    gnome-keyring
    libsecret
    zenity
    gpg-tui
  ];

  services.gnome.gnome-keyring.enable = true;
  programs.seahorse.enable = true;
  
  nixpkgs.config = { allowBroken = true; allowUnfree = true; };
}
