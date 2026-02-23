{ config, inputs, pkgs, lib, ... }:
{
  environment.systemPackages = with pkgs; [
    nh
    lsd
    wget
    fastfetch
    rage
    uutils-coreutils-noprefix
    bat
    btop
    killall
    wineWow64Packages.stable    
    wineWow64Packages.staging
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
