{
  config,
  inputs,
  pkgs,
  lib,
  ...
}:
{
  imports = [ inputs.nixcord.homeModules.nixcord ];

  home.packages = [
    pkgs.discover-overlay
    pkgs.arrpc
    (pkgs.discord.override {
      withVencord = true;
    })
  ];

}
