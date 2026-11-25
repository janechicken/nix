{
  config,
  inputs,
  pkgs,
  lib,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    age-plugin-fido2-hmac
    yubikey-manager
    yubikey-personalization
    yubikey-agent
    pam_u2f
  ];
  # Host-independent relying-party ID so one registered credential works on both
  # hosts. Keys must be registered against the same values:
  #   pamu2fcfg -o pam://nixos-jane -i pam://nixos-jane
  # `control` stays at the default "sufficient", so an unplugged key or a missed
  # touch always falls through to the password prompt (zero lockout risk).
  security.pam.u2f.settings = {
    origin = "pam://nixos-jane";
    # Only consulted for credentials from pamu2fcfg <= 1.0.8; defaults to the
    # origin value otherwise. Kept equal to origin to match pamu2fcfg -i.
    appid = "pam://nixos-jane";
    cue = true;
    cue_prompt = "Please touch your YubiKey";
  };

  security.pam.services = {
    login.u2fAuth = true;
    sudo.u2fAuth = true;
  };
}
