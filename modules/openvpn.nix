{ config, inputs, pkgs, lib }:
{
  services.openvpn = {
    enable = true;
  };
}
