{ config, inputs, pkgs, lib, ... }:
{
  environment.systemPackages = with pkgs; [
    age-plugin-fido2-hmac
    yubikey-manager
    yubikey-personalization
    yubikey-agent
    pam_u2f
  ];
  security.pam.services = {
    login.u2fAuth = true;
    sudo.u2fAuth = true;
  };
}
