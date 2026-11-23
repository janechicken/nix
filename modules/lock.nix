{ config, pkgs, ... }:

let
  cfg = config.programs.i3lock;
  jane = config.users.users.jane;

  # i3lock must run as the session user inside her X session: as root it has no
  # DISPLAY/XAUTHORITY and PAM would check root's password. Prefer the setuid
  # wrapper (U2F needs raw HID access), fall back to the plain binary.
  i3lock =
    if cfg.u2fSupport then
      "${config.security.wrapperDir}/i3lock"
    else
      "${cfg.package}/bin/i3lock";

  # Runs from the post-resume hook as root and hands the lock to jane's session
  # through systemd-run, so it lands on the live X display.
  lockOnResume = pkgs.writeShellScript "lock-on-resume" ''
    set -eu

    [ -x "${i3lock}" ] || exit 0
    [ -f "${jane.home}/.Xauthority" ] || exit 0

    # startx binds the first free X socket; that is the session to lock.
    display=""
    for sock in /tmp/.X11-unix/X*; do
      [ -e "$sock" ] || continue
      display=":''${sock##*/X}"
      break
    done
    [ -n "$display" ] || exit 0

    exec ${config.systemd.package}/bin/systemd-run --quiet --collect \
      --uid=${jane.name} \
      --setenv=DISPLAY="$display" \
      --setenv=XAUTHORITY="${jane.home}/.Xauthority" \
      "${i3lock}" -c 000000
  '';
in
{
  programs.i3lock = {
    enable = true;
    u2fSupport = true;
  };

  # Lock the screen when the machine wakes from suspend so a resumed laptop
  # isn't left in an unlocked session. The previous version was a root oneshot
  # pulled in by `suspend.target` with no DISPLAY/XAUTHORITY: i3lock always
  # failed, and being ordered after the target it raced the sleep instead of
  # covering the screen.
  powerManagement.resumeCommands = ''
    ${lockOnResume} || true
  '';
}
