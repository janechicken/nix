{ config, inputs, pkgs, lib, ... }:
{
  environment.systemPackages = [ pkgs.openvpn pkgs.mullvad-vpn ];
}
