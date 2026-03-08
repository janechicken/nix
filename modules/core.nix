{
  config,
  inputs,
  pkgs,
  lib,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    nh
    lsd
    wget
    fastfetch
    uutils-coreutils-noprefix
    (lib.meta.setPrio 5 procps)
    (lib.meta.setPrio 6 toybox)
    bat
    btop
    wineWow64Packages.stable
    wineWow64Packages.staging
    winetricks
    home-manager
    zenity
    appimage-run
    p7zip-rar
    qrrs
  ];

  nixpkgs.config = {
    allowBroken = true;
    allowUnfree = true;
  };
}
