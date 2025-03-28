{ config, inputs, pkgs, lib, ... }: {
  environment.systemPackages = with pkgs; [
    reaper
    (yabridge.override { wine = wineWowPackages.full; })
    (yabridgectl.override { wine = wineWowPackages.full; })
    lsp-plugins
  ];
}
