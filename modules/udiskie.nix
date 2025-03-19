{ config, inputs, pkgs, lib, ... }:
{

  environment.systemPackages = with pkgs; [
  # udiskie
  udisks2
  ];
  # services.udiskie.enable = true;
  services.udisks2.enable = true;
}
