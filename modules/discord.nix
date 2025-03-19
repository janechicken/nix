{ config, inputs, pkgs, lib, ... }:
{
  home.packages = with pkgs; [
    (discord.override {
      withVencord = true;
     })
  ];
}
