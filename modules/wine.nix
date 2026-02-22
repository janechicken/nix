{ config, pkgs, lib, ... }: {

  environment.systemPackages = with pkgs;
    [
      wineWow64Packages.stableFull
    ];
}
