{ config, inputs, pkgs, lib, ... }:
{
  services.udiskie.enable = true;
  services.udisks2.enable = true;
}
