{ config, inputs, pkgs, lib, ... }: {
  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;
  };

  environment.systemPackages = with pkgs; [
    mangohud
    protonup
    (heroic.override { extraPkgs = (pkgs: [ pkgs.zip pkgs.unzip pkgs.rar pkgs.unrar ]); })
  ];
  programs.gamemode.enable = true;
}
