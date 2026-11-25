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
    # TTY `login` stays password-only: pam_u2f is `sufficient`, so a successful
    # touch returns success right there and pam_unix never runs - PAM_AUTHTOK
    # stays unset, and pam_gnome_keyring (optional, part of the `unix-early`
    # block that nixpkgs emits when enableGnomeKeyring is set) then has no
    # password to unlock the login keyring with. The YubiKey still guards
    # `sudo` (below), `hyprlock` (modules/hyprland.nix) and LUKS/FIDO2
    # (boot.initrd.luks.devices in the host config).
    login.u2f.enable = false;
    sudo.u2f.enable = true;
  };
}
