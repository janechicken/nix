{ config, inputs, pkgs, lib, ... }:
{
  programs.i3lock = {
    enable = true;
    u2fSupport = true;
  };

  # Lock the screen when the machine is suspended and woken again, so a
  # resumed laptop isn't left in an unlocked session. Runs on `post-resume`
  # (not `pre-suspend`) so the lock actually covers the screen before the
  # user can interact. Both laptops import this module.
  systemd.services."lock-on-resume" = {
    description = "Lock screen on resume from suspend";
    wantedBy = [ "suspend.target" ];
    after = [ "suspend.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.i3lock}/bin/i3lock -c 000000";
    };
  };
}
