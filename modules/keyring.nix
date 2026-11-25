{
  config,
  inputs,
  pkgs,
  lib,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    libsecret
    gnome-keyring
    gcr_4
  ];

  # No `services.dbus.packages` here on purpose (it used to list
  # `[ gnome-keyring gcr_4 ]`): nixpkgs' services.gnome.gnome-keyring module
  # (nixos/modules/services/desktops/gnome/gnome-keyring.nix) already sets
  #   services.dbus.packages = [ pkgs.gnome-keyring pkgs.gcr_3 ];
  # and those two are exactly the packages that ship the session-bus activatable
  # services makeDBusConf puts into /etc/dbus-1/session.conf:
  #   gnome-keyring: org.freedesktop.secrets, org.gnome.keyring,
  #                  org.freedesktop.impl.portal.Secret
  #                  (share/dbus-1/services)
  #   gcr_3:         org.gnome.keyring.{Private,System}Prompter
  #                  (share/dbus-1/services)
  # gcr_4 ships no share/dbus-1 at all, so the old entry only duplicated
  # gnome-keyring and added nothing. gcr_4 stays installed (above) for the
  # portal/prompter UI, not for D-Bus activation.

  programs.seahorse.enable = true;

  # Also sets security.pam.services.login.enableGnomeKeyring; kept explicit so
  # the TTY login stack (pam_unix -> pam_gnome_keyring) is visible here next to
  # the PAM modules it depends on.
  services.gnome.gnome-keyring.enable = true;
  security.pam.services = {
    login.enableGnomeKeyring = true;
  };
}
