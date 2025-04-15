{ config, inputs, pkgs, lib, ... }: {
  programs.steam = {
    enable = true;
    gamescopeSession = true;
  };

  environment.systemPackages = with pkgs; [ mangohud protonup ];
  programs.gamemode.enable = true;
}
