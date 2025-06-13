{ config, inputs, pkgs, lib, ... }: {
  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;
  };

  environment.systemPackages = with pkgs; [
    mangohud
    protonup
    heroic
  ];
  programs.gamemode.enable = true;
  programs.gamescope.enable = true;
}
