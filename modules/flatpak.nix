{ config, inputs, pkgs, lib, ... }: {
  services.flatpak.enable = true;
  environment.systemPackages = with pkgs; [
   ];
}
