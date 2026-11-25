{
  config,
  pkgs,
  lib,
  ...
}:

let
  # `pi` (pi-nix) is not a nixpkgs wrapper flag: T3 Code's pi provider spawns the
  # bare `pi` command (packages/provider-pi `binaryPath: "pi"`), so it has to be
  # on the desktop app's PATH. Putting it in the wrapper keeps the pi provider
  # working even when t3code-desktop is started without the home-manager session
  # PATH (systemd unit, rofi/`hyprctl dispatch exec`, desktop entry).
  piEnabled = config.programs.pi.coding-agent.enable or false;
  piPackage = lib.optional piEnabled config.programs.pi.coding-agent.finalPackage;
  t3codePkg = pkgs.t3code.override {
    enableCodex = true;
    enableConnect = true;
    enableGitHub = true;
    enableGit = true;
    enableResourceMonitor = true;
    extraRuntimePackages = piPackage;
  };

  # ===========================================================================
  # Background daemon <-> t3code-desktop coexistence
  #
  # Verified against the t3code 0.1.11 build in the store
  # (`apps/server/dist/*.mjs`, `apps/desktop/dist-electron/main.cjs`):
  #
  # 1. A T3 home (`$T3CODE_HOME`, i.e. `~/.t3`) is owned *exclusively* through an
  #    exclusive SQLite transaction on `<home>/userdata/server-owner.sqlite`
  #    (`src/serverOwnership.ts`, `openOwnershipLock`). The lock file never holds
  #    data and must not be deleted; the kernel drops the lock when the holder
  #    dies, even on SIGKILL.
  #
  # 2. `t3 serve` (our daemon) tries that lock with `busy_timeout = 250`, and on
  #    failure dies immediately with `ServerAlreadyRunningError`, whose
  #    `errorExitCode` is 78 (`relayTracing-*.mjs`).
  #
  # 3. `t3code-desktop` does NOT attach to a running `t3 serve`. It always spawns
  #    its own embedded backend (`apps/server/dist/bin.mjs`) and, when that exits
  #    with 78, `DesktopBackendPool`'s `onStateDirOwned` shows the
  #    "Another T3 Code server ... is using this T3 home" box and quits
  #    (`main.cjs` -> `homeOwnedMessage`, `electronApp.quit`). There is no client
  #    mode for a local server, and pairing with it over the network is a manual,
  #    per-launch flow (separate T3 home + relay/SSH environment).
  #
  # 4. Before spawning that backend the app *waits* for the home to become free:
  #    `startLocalBackend` calls `awaitHomeOwnershipRelease`, which polls
  #    `server-owner.sqlite` every 250 ms for up to
  #    `HOME_OWNERSHIP_RELEASE_GRACE = BACKEND_QUIT_STOP_TIMEOUT (5 s + 2 s) + 3 s`
  #    = 10 s. That 10 s window is what makes a seamless handoff possible.
  #
  # 5. `t3 __service-launcher` (what upstream's `t3 service install` writes as
  #    `ExecStart`) implements the *other* half only: its child `t3 serve` exits
  #    78 when someone else owns the home, and the launcher then idles
  #    (`#idleWhileStateDirOwned`), polls every 30 s and reclaims the home after
  #    two free probes (`#reclaimStateDir` -> `#claimServing`). It never asks the
  #    desktop to wait, so it cannot hand the home over. On top of that it needs
  #    `<home>/runtime/service-state.json` (it throws "Service state is invalid or
  #    unsupported." without it), a pinned runtime tree copied into
  #    `<home>/runtime/versions/<version>/t3` by `t3 service install` (an upstream
  #    tarball download, not the Nix build), and it records the server as
  #    `serviceManaged: true`, which is the message variant that tells the user to
  #    run `t3 service uninstall`. So it is the wrong tool for a Nix-managed
  #    daemon that has to yield to the desktop app. (`T3_BOOT_SERVICE_UNIT` is
  #    read by that launcher only - it locates the unit file to repoint after an
  #    update - so the unit below does not set it, and `runtime/service-serving.lock`
  #    is not created either: it is the launcher's "a server is (about to be)
  #    running" marker, and only the desktop's *SSH* helper (`home_owned`) looks at
  #    it. The desktop's local path checks `server-owner.sqlite` alone.)
  #
  # Therefore the daemon below is a small supervisor that provides both halves:
  # it runs `t3 serve` while the desktop app is closed and releases the home
  # (SIGTERM to `t3 serve`) as soon as the desktop app starts, then takes it back
  # when the app exits. The signal both sides agree on is an flock on
  # `$XDG_RUNTIME_DIR/t3code-desktop.lock`: `t3code-desktop` holds it exclusively
  # for as long as the app runs, the daemon only ever probes it non-blocking.
  #
  # Timing: probe interval 0.5 s + at most 4 s for `t3 serve` to shut down (then
  # SIGKILL) = under 5 s, comfortably inside the app's 10 s release grace. The
  # app therefore starts with no error box at all, and it shares `~/.t3`
  # (`server-owner.sqlite`, `userdata/statev2.sqlite`, `settings.json`) because
  # both processes use the same T3 home - just not at the same time.
  #
  # Honest trade-offs of this design (there is no zero-cost alternative, the
  # desktop app requires exclusive ownership):
  #   - Opening/closing the desktop app moves the server between the daemon and
  #     the app's embedded backend, so a phone connected over T3 Connect drops
  #     once and reconnects (a second or two).
  #   - While the desktop app is open, remote clients reach *its* backend, so the
  #     app's own sharing/exposure settings apply (Settings -> Sharing & access).
  #     Both processes read the same `~/.t3/userdata/settings.json`, so T3 Connect
  #     stays configured; only the serving process changes.
  #   - If the desktop wrapper is SIGKILLed the daemon may try to start while the
  #     app still runs; `t3 serve` then just exits 78 and the supervisor retries
  #     every 2 s until the app is gone. Self-healing, no state to clean up.
  # ===========================================================================
  t3Home = "${config.home.homeDirectory}/.t3";

  # Daemon: `t3 serve` with the launcher's idle/reclaim semantics plus a
  # cooperative yield (see the block above).
  t3codeDaemon = pkgs.writeShellApplication {
    name = "t3code-daemon";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
    ];
    meta = {
      description = "T3 Code headless server that yields the T3 home to t3code-desktop";
      mainProgram = "t3code-daemon";
    };
    text = ''
      lock="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/t3code-desktop.lock"
      serve_pid=""

      # True while `t3code-desktop` holds the lock, i.e. while the desktop app is
      # running (or its embedded backend still owns the T3 home).
      desktop_running() {
        [ -e "$lock" ] || return 1
        ! flock -n "$lock" true 2>/dev/null
      }

      # Bounded, graceful stop: `t3 serve` shuts down on SIGTERM; SIGKILL after
      # 4 s is safe (SQLite WAL, and the ownership lock is released by the OS).
      terminate_serve() {
        [ -n "$serve_pid" ] || return 0
        kill -TERM "$serve_pid" 2>/dev/null || true
        for _ in $(seq 1 40); do
          kill -0 "$serve_pid" 2>/dev/null || break
          sleep 0.1
        done
        kill -KILL "$serve_pid" 2>/dev/null || true
      }

      # `systemctl --user stop t3code`: KillMode=mixed only signals this script.
      on_stop() {
        terminate_serve
        wait 2>/dev/null || true
        exit 0
      }
      trap on_stop TERM INT

      while :; do
        if desktop_running; then
          sleep 0.5
          continue
        fi

        # `lib.getExe'`, not `lib.getExe`: the package's mainProgram is
        # `t3code-desktop`, not the `t3` CLI.
        ${lib.getExe' t3codePkg "t3"} serve &
        serve_pid=$!

        # Serve until the server exits on its own (78 = the desktop's own backend
        # took the home) or the desktop app asks for the home.
        while kill -0 "$serve_pid" 2>/dev/null && ! desktop_running; do
          sleep 0.5
        done

        if kill -0 "$serve_pid" 2>/dev/null; then
          echo "[t3code] t3code-desktop is starting: releasing the T3 home" >&2
          terminate_serve
        fi

        status=0
        wait "$serve_pid" || status=$?
        serve_pid=""

        # 78: another server owns the home. Back off instead of spinning; the
        # desktop app keeps the home until it exits.
        if [ "$status" -ne 0 ]; then
          sleep 2
        fi
      done
    '';
  };

  # `t3code-desktop`, but cooperative: hold the handoff lock while the app runs.
  t3codeDesktopSession = pkgs.writeShellApplication {
    name = "t3code-desktop";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
    ];
    meta = {
      description = "T3 Code desktop app that hands the T3 home over from t3code.service";
      mainProgram = "t3code-desktop";
    };
    text = ''
      lock="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/t3code-desktop.lock"
      mkdir -p "$(dirname "$lock")" 2>/dev/null || true

      # Tell the background daemon (t3code.service) to release
      # ~/.t3/userdata/server-owner.sqlite; it does so within a second and the app
      # itself waits up to 10 s for it, so no error box appears. A second launch
      # cannot take the lock - it runs the binary anyway and Electron's
      # single-instance handling focuses the existing window.
      exec 9>>"$lock" || true
      flock -w 1 9 2>/dev/null || true

      # Keep the lock out of Electron and out of every agent/terminal process it
      # spawns, so the daemon can reclaim the T3 home the moment the app exits,
      # even if one of those processes lingers.
      ( exec 9>&-; exec ${lib.getExe' t3codePkg "t3code-desktop"} "$@" )
    '';
  };

  # One package, so `t3code-desktop` in PATH (and therefore the desktop entry's
  # `Exec=t3code-desktop %U`) is always the cooperative wrapper. Two separate
  # home-manager packages would instead collide on `bin/t3code-desktop`, and the
  # profile's ignoreCollisions would silently pick whichever came first.
  # symlinkJoin (lndir) keeps `$out/bin` a real directory, so replacing the one
  # entry is enough; every other wrapper/env from `t3codePkg` stays untouched.
  t3codeWithDesktopSession = pkgs.symlinkJoin {
    name = "t3code-${t3codePkg.version}";
    paths = [ t3codePkg ];
    postBuild = ''
      rm "$out/bin/t3code-desktop"
      ln -s ${t3codeDesktopSession}/bin/t3code-desktop "$out/bin/t3code-desktop"
    '';
    meta = t3codePkg.meta;
  };
in
{
  # ===========================================================================
  # T3 Code — minimal web GUI / desktop shell for coding agents
  # (https://t3.codes, github:pingdotgg/t3code).
  #
  # Version: the packaging lives in pkgs/t3code/ (bumped to 0.1.11, the latest
  # upstream stable release) and overlays/t3code.nix replaces only `t3code`.
  # nixos-unstable is still on 0.1.8, and staying on the pinned nixpkgs means
  # linux-mahua / mesa-mahua keep their existing store paths (no rebuild).
  #
  # Wrapper PATH: codex + gh + git (nixpkgs defaults) plus pi. Codex is kept
  # even though the app currently has it disabled, so enabling the provider in
  # the UI needs no rebuild. Claude / OpenCode / Cursor / jj / glab are left off
  # — they are not used here.
  #
  # The resource monitor sidecar (Rust, built from source) stays enabled: it
  # feeds the app's CPU/RAM panel.
  #
  # T3 Connect is on: `enableConnect` bakes upstream's public relay/Clerk
  # identifiers (relay.t3.codes, the Clerk publishable key and JWT template,
  # straight from upstream's `.env.example`) into the web/server/desktop
  # bundles, and the wrapper exports T3CODE_CLOUDFLARED_PATH for the relay
  # tunnel. `cloudflared` comes from nixpkgs (built with `buildGo127Module`),
  # so both hosts get it straight from `cache.nixos.org` (2026.10.7, above
  # upstream's 2026.10.3 minimum): a download, not a build.
  # ===========================================================================
  home.packages = [ t3codeWithDesktopSession ];

  # Headless T3 Code daemon. Starts with the user manager (`default.target`), so
  # it is up on a plain TTY login with no Hyprland/Wayland and keeps T3 Connect
  # reachable from the phone. It is not upstream's `t3 __service-launcher`: that
  # one needs `~/.t3/runtime/service-state.json` plus a `runtime/versions/<v>/t3`
  # tree copied by `t3 service install`, and it never hands the T3 home over to
  # `t3code-desktop` (see the block above). The supervisor in `t3code-daemon`
  # provides the same idle/reclaim behaviour and additionally yields to the
  # desktop app, so `t3code-desktop` opens with no "Another T3 Code server is
  # using this T3 home" error while both share `~/.t3`.
  #
  # Do not run `t3 service install|uninstall|restart` or `t3 update`: this unit is
  # declarative and the `t3` binary comes from the Nix store.
  systemd.user.services.t3code = {
    Unit = {
      Description = "T3 Code server (yields the T3 home to t3code-desktop)";
      After = [ "network-online.target" ];
      StartLimitIntervalSec = 300;
      StartLimitBurst = 5;
    };
    Service = {
      Type = "simple";
      WorkingDirectory = "%h";
      # Absolute, exactly like upstream's rendered unit: the server reads
      # `Environment=T3CODE_HOME=` back from this file to detect a stale
      # launcher, and `%h` would not resolve there.
      Environment = [ "T3CODE_HOME=${t3Home}" ];
      ExecStart = "${t3codeDaemon}/bin/t3code-daemon";
      KillMode = "mixed";
      TimeoutStopSec = 30;
      OOMPolicy = "continue";
      Restart = "always";
      RestartSec = 5;
      CPUWeight = 1000;
      IOWeight = 1000;
      MemoryLow = "1536M";
      OOMScoreAdjust = 100;
      ManagedOOMPreference = "avoid";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
