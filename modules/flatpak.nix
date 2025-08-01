{ config, inputs, pkgs, lib, ... }: {
  services.flatpak.enable = true;
  environment.profiles =
    [ "$HOME/.local/share/flatpak/exports" "/var/lib/flatpak/exports" ];
  environment.systemPackages = with pkgs; [ ];
}
