{ config, inputs, pkgs, lib, ... }: {
  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;
  };

  environment.systemPackages = with pkgs; [
    (mangohud.override { nvidiaSupport = false; })
    protonup
    (heroic.override { extraPkgs = pkgs: [ pkgs.gamescope ]; })

  ];
  programs.gamemode.enable = true;
  programs.gamescope.enable = true;
}
