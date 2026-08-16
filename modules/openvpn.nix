{ config, inputs, pkgs, lib, ... }:
{
  services.mullvad-vpn.enable = true;
  environment.systemPackages = [ pkgs.openvpn pkgs.mullvad-vpn ];
}
