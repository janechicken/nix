{ config, inputs, pkgs, lib, ... }:
{
  environment.systemPackages = [ pkgs.openvpn ];
}
