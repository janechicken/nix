{
  config,
  inputs,
  pkgs,
  lib,
  ...
}:
let
  # gpg-agent is a long-running user daemon, so its own environment says nothing
  # about where a given request comes from, and gpg-agent happily leaks it into
  # pinentry: an agent started from the desktop still exports its
  # WAYLAND_DISPLAY/DISPLAY to a pinentry that was triggered by an SSH login,
  # even after `updatestartuptty` was run from that SSH shell (verified with
  # gpg 2.4). What gpg-agent *does* forward per request is the calling client's
  # environment (DISPLAY, WAYLAND_DISPLAY, XDG_RUNTIME_DIR, GPG_TTY,
  # PINENTRY_USER_DATA, ...) plus `--display <DISPLAY>` in argv. So the reliable
  # signals are:
  #   - PINENTRY_USER_DATA, set by the shell hooks at the bottom of this file for
  #     remote sessions, which gpg passes through untouched;
  #   - the client's own display, after checking that it is still alive.
  # GPG_TTY is *not* usable: a compositor started from a text console hands its
  # stale /dev/ttyN down to every GUI application.
  pinentryAuto = pkgs.writeShellApplication {
    name = "pinentry-auto";
    runtimeInputs = [ pkgs.coreutils ];
    meta = {
      description = "pinentry wrapper: pinentry-rofi in GUI sessions, TTY pinentry otherwise";
      mainProgram = "pinentry-auto";
    };
    text = ''
      tty_pinentry() {
        # pinentry-curses needs a real terminal; the plain tty flavour is the
        # right choice when TERM says there is none (cron, `dumb`, TERM unset).
        if [[ -z ''${TERM:-} || ''${TERM:-} == dumb ]]; then
          exec ${lib.getExe pkgs.pinentry-tty} "$@"
        fi
        exec ${lib.getExe pkgs.pinentry-curses} "$@"
      }

      # gpg-agent passes --display for the client's DISPLAY (long form, separate
      # argument); accept the --display=VALUE and -D VALUE spellings too.
      display_arg=
      expect_display=0
      for arg in "$@"; do
        if [[ $expect_display == 1 ]]; then
          display_arg=$arg
          expect_display=0
          continue
        fi
        case $arg in
          --display | -D) expect_display=1 ;;
          --display=*) display_arg=''${arg#--display=} ;;
        esac
      done

      # Explicit opt-out/opt-in via PINENTRY_USER_DATA, which gpg forwards from
      # the calling shell. `USE_TTY=1` keeps the prompt on the terminal even
      # when a desktop session is logged in at the same time; `USE_TTY=0` forces
      # the GUI pinentry regardless.
      case ''${PINENTRY_USER_DATA:-} in
        *[Uu][Ss][Ee]_[Tt][Tt][Yy]=0*) ;;
        *[Uu][Ss][Ee]_[Tt][Tt][Yy]* | *[Tt][Tt][Yy]*) tty_pinentry "$@" ;;
      esac

      # Wayland: WAYLAND_DISPLAY must name a live socket, otherwise a leftover
      # value inherited from the agent would send the prompt to the desktop.
      wayland_live=0
      if [[ -n ''${WAYLAND_DISPLAY:-} ]]; then
        case $WAYLAND_DISPLAY in
          /*) wayland_socket=$WAYLAND_DISPLAY ;;
          *) wayland_socket=''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/$WAYLAND_DISPLAY ;;
        esac
        if [[ -S $wayland_socket ]]; then
          wayland_live=1
        fi
      fi

      # X11: only trust a local display whose socket exists; a `host:0` display
      # is only ever reported for a client with working X forwarding (ssh -X),
      # so trust that one.
      x11_live=0
      x_display=''${display_arg:-''${DISPLAY:-}}
      if [[ -n $x_display ]]; then
        case $x_display in
          :* | unix:*)
            x_number=''${x_display#:}
            x_number=''${x_number#unix:}
            x_number=''${x_number%%.*}
            if [[ -S /tmp/.X11-unix/X$x_number ]]; then
              x11_live=1
            fi
            ;;
          *) x11_live=1 ;;
        esac
      fi

      if [[ $wayland_live == 1 ]]; then
        exec ${lib.getExe pkgs.pinentry-rofi} "$@"
      fi

      if [[ $x11_live == 1 ]]; then
        # rofi 2.x selects its Wayland backend whenever WAYLAND_DISPLAY is set
        # and non-empty, so drop a stale value to get the X11 backend.
        unset WAYLAND_DISPLAY
        # pinentry-rofi defaults --display to ":0"; hand it the real one when
        # gpg-agent did not.
        if [[ -z $display_arg && -n ''${DISPLAY:-} ]]; then
          set -- --display "$DISPLAY" "$@"
        fi
        exec ${lib.getExe pkgs.pinentry-rofi} "$@"
      fi

      tty_pinentry "$@"
    '';
  };

  # `services.gpg-agent.enableZshIntegration` already exports GPG_TTY and runs
  # `gpg-connect-agent updatestartuptty /bye`. On top of that, mark remote
  # shells without a graphical display: a passphrase typed over SSH must not
  # pop up a rofi prompt on a desktop that happens to be logged in meanwhile.
  # gpg forwards PINENTRY_USER_DATA per request, so this stays local to the
  # session. It is deliberately not set in local console shells: a compositor
  # started from such a shell would inherit it and every GUI prompt would then
  # be redirected to the console.
  pinentryUserDataHook = ''
    if [[ -z ''${WAYLAND_DISPLAY:-} && -z ''${DISPLAY:-} && -n ''${SSH_CONNECTION:-}''${SSH_TTY:-} ]]; then
      case ''${PINENTRY_USER_DATA:-} in
        *[Tt][Tt][Yy]*) ;;
        "") export PINENTRY_USER_DATA=USE_TTY=1 ;;
        *) export PINENTRY_USER_DATA="USE_TTY=1;$PINENTRY_USER_DATA" ;;
      esac
    fi
  '';
in
{
  home.packages = with pkgs; [ kdePackages.kleopatra gpg-tui ];

  services.gpg-agent = {
    enable = true;
    defaultCacheTtl = 36000;
    maxCacheTtl = 36000;
    defaultCacheTtlSsh = 36000;
    maxCacheTtlSsh = 36000;
    enableSshSupport = true;
    pinentry.package = pinentryAuto;
    pinentry.program = "pinentry-auto";
    enableZshIntegration = true;
    enableBashIntegration = true;
  };
  programs.gpg = {
    enable = true;
    settings = { default-key = "78704CDE27D95D3E17065F23ACC77E2F16E02769"; };
  };

  # `.zshenv` rather than `.zshrc`, so `ssh host <command>` (non-interactive)
  # is covered too. The bash hook is inert today (`programs.bash.enable` is off
  # on both hosts) but keeps the behaviour if bash is ever enabled.
  programs.zsh.envExtra = pinentryUserDataHook;
  programs.bash.initExtra = pinentryUserDataHook;
}
