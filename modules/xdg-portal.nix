{ pkgs, lib, ... }:

{
  xdg.portal = {
    enable = true;
    # gtk: FileChooser/etc. Screenshot stays flameshot (Awesome Print keys),
    # not a portal backend — gnome is settings-only on X11, xapp pulls MATE.
    config.common.default = [ "gtk" ];
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  # startx never reaches graphical-session.target (RefuseManualStart).
  # Portal units PartOf/After that target; binder oneshot with BindsTo
  # pulls it up. xinitrc starts/stops this around awesome.
  systemd.user.services.awesome-graphical-session = {
    description = "Awesome WM graphical session binder";
    unitConfig = {
      BindsTo = "graphical-session.target";
      Wants = "graphical-session-pre.target";
      After = "graphical-session-pre.target";
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/true";
    };
  };

  # startx + Awesome: DISPLAY may be unset when portal units activate.
  # Hardcode :0 and restart on "cannot open display".
  systemd.user.services.xdg-desktop-portal-gtk = {
    serviceConfig = {
      Environment = "DISPLAY=:0";
      Restart = "on-failure";
      RestartSec = "3s";
    };
  };
}
