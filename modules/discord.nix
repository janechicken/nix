{
  config,
  inputs,
  pkgs,
  lib,
  ...
}:
{
  imports = [ inputs.nixcord.homeModules.nixcord ];

  home.packages =
    if pkgs.stdenv.hostPlatform.isx86_64 then
      [
        pkgs.discover-overlay
        pkgs.arrpc
        (pkgs.discord.override {
          withVencord = true;
        })
      ]
    else
      [
        pkgs.vesktop
      ];
}
