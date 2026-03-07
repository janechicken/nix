{ config, inputs, pkgs, lib, ... }:
{
  environment.systemPackages = with pkgs; [
    nh
    lsd
    wget
    fastfetch
    uutils-coreutils-noprefix
    bat
    btop
    killall
    toybox
    wineWow64Packages.stable    
    wineWow64Packages.staging
    winetricks
    home-manager
    zenity
    appimage-run
    p7zip-rar
    qrrs
  ];

  nixpkgs.config = { allowBroken = true; allowUnfree = true; };
}
