{ config, lib, pkgs, ... }:
{
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;
  # virt-manager provisions its qemu:///system autoconnect via dconf profiles
  programs.dconf.enable = true;
}
