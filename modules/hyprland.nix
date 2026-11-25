# NixOS system module for Hyprland (Wayland) — used on hosts migrating off X11/AwesomeWM.
# Keeps all overrides out of global overlays so cache.nixos.org hits remain intact.
{
  pkgs,
  ...
}:

{
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # programs.hyprland enables xdg-desktop-portal-hyprland and sets hyprland-portals.conf;
  # add the GTK backend for FileChooser / Settings fallback.
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  # GPU-accelerated Wayland lock screen + systemd user hypridle service.
  # Add FIDO2/U2F PAM support matching modules/fido.nix.
  programs.hyprlock.enable = true;
  security.pam.services.hyprlock.u2f.enable = true;

  # Polkit for GUI privilege elevation (paired with hyprpolkitagent in HM).
  security.polkit.enable = true;

  # Prefer native Wayland backends for Electron/Chromium, GTK, Qt, SDL, and Firefox/LibreWolf.
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    GDK_BACKEND = "wayland,x11,*";
    QT_QPA_PLATFORM = "wayland;xcb";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    SDL_VIDEODRIVER = "wayland";
    CLUTTER_BACKEND = "wayland";
    MOZ_ENABLE_WAYLAND = "1";
  };
}
