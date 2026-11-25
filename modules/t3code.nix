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

  t3Home = "${config.home.homeDirectory}/.t3";

  # ===========================================================================
  # Architecture: one permanent backend, desktop as a pure client
  #
  # 1. `t3code.service` owns the T3 home (`~/.t3`) permanently and serves
  #    `t3 serve --host 127.0.0.1 --port 3773`. The explicit `--host 127.0.0.1`
  #    matters: bare `t3 serve` binds all interfaces. The fixed port `3773`
  #    matches the T3 Connect origin that was confirmed once, so `cloudflared`
  #    (and therefore remote clients) resume without re-confirming a new origin.
  #    A T3 home is owned exclusively through an exclusive SQLite transaction on
  #    `<home>/userdata/server-owner.sqlite`; only one process can serve it.
  #
  # 2. `t3code-desktop` uses the same `T3CODE_HOME` (`~/.t3`) but runs in
  #    pure-client mode: `localEnvironmentEnabled: false` in
  #    `userdata/desktop-settings.json` makes `startLocalBackend` return before
  #    the `server-owner.sqlite` ownership check, so the app never spawns an
  #    embedded backend and never competes for the home. `t3 app` IPC, Clerk
  #    sign-in, `client-settings.json`, window bounds and file drag-and-drop are
  #    untouched; only the local backend is skipped.
  #
  # 3. One-time pairing: `t3 pair` prints
  #    `http://127.0.0.1:3773/pair#token=...`; adding that URL in
  #    Settings -> Environments creates a renewable DPoP session (auto-renewed
  #    within a 30-day window) stored in `userdata/connection-catalog.json`
  #    (encrypted via `gnome-keyring`) plus `~/.config/t3code-v2/IndexedDB`.
  #
  # There is no flock handoff: the server never yields and the desktop never
  # takes over, so opening or closing the app does not move the backend, does not
  # drop connected clients, and cannot race a running `t3 serve`.
  # ===========================================================================

  # `t3code-desktop`, but forced into pure-client mode before launch. The settings
  # file is rewritten only when needed and only that one key, so window bounds and
  # every other field survive. Failures are non-fatal: the app is launched anyway.
  t3codeDesktopClient = pkgs.writeShellApplication {
    name = "t3code-desktop";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    meta = {
      description = "T3 Code desktop app in pure-client mode (backend from t3code.service)";
      mainProgram = "t3code-desktop";
    };
    text = ''
      home_dir="''${T3CODE_HOME:-${t3Home}}"
      state_dir="$home_dir/userdata"
      settings="$state_dir/desktop-settings.json"

      mkdir -p "$state_dir"

      if [ -f "$settings" ]; then
        # `jq -e` exits 1 when the expression is false/null, so this is the
        # "anything but exactly false" test.
        if ! jq -e '.localEnvironmentEnabled == false' "$settings" >/dev/null 2>&1; then
          if tmp="$(mktemp "$state_dir/.desktop-settings.XXXXXX")"; then
            if jq '.localEnvironmentEnabled = false' "$settings" >"$tmp" 2>/dev/null; then
              mv "$tmp" "$settings" || rm -f "$tmp" || true
            else
              rm -f "$tmp" || true
            fi
          fi
        fi
      else
        if tmp="$(mktemp "$state_dir/.desktop-settings.XXXXXX")"; then
          if printf '%s\n' '{"localEnvironmentEnabled":false}' >"$tmp"; then
            mv "$tmp" "$settings" || rm -f "$tmp" || true
          else
            rm -f "$tmp" || true
          fi
        fi
      fi

      exec ${lib.getExe' t3codePkg "t3code-desktop"} "$@"
    '';
  };

  # One package, so `t3code-desktop` in PATH (and therefore the desktop entry's
  # `Exec=t3code-desktop %U`) is always the pure-client wrapper. Two separate
  # home-manager packages would instead collide on `bin/t3code-desktop`, and the
  # profile's ignoreCollisions would silently pick whichever came first.
  # symlinkJoin (lndir) keeps `$out/bin` a real directory, so replacing the one
  # entry is enough; every other wrapper/env from `t3codePkg` stays untouched.
  t3codeWithDesktopClient = pkgs.symlinkJoin {
    name = "t3code-${t3codePkg.version}";
    paths = [ t3codePkg ];
    postBuild = ''
      rm "$out/bin/t3code-desktop"
      ln -s ${t3codeDesktopClient}/bin/t3code-desktop "$out/bin/t3code-desktop"
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
  home.packages = [ t3codeWithDesktopClient ];

  # Headless T3 Code server, the only owner of `~/.t3`. Starts with the user
  # manager (`default.target`), so it is up on a plain TTY login with no
  # Hyprland/Wayland and keeps T3 Connect reachable from the phone. It is not
  # upstream's `t3 __service-launcher`: that one needs `~/.t3/runtime/service-state.json`
  # plus a `runtime/versions/<v>/t3` tree copied by `t3 service install`, and it
  # records the server as `serviceManaged`, which points the user at
  # `t3 service uninstall`. Here the `t3` binary comes from the Nix store instead.
  #
  # Do not run `t3 service install|uninstall|restart` or `t3 update`: this unit is
  # declarative.
  systemd.user.services.t3code = {
    Unit = {
      Description = "T3 Code headless server";
      # No burst cap: `RestartSec = 5` already paces retries, and a one-time
      # transition while an older desktop backend still holds `~/.t3` must never
      # end in `start-limit-hit`.
      StartLimitIntervalSec = 0;
    };
    Service = {
      Type = "simple";
      WorkingDirectory = "%h";
      # Absolute, exactly like upstream's rendered unit: the server reads
      # `Environment=T3CODE_HOME=` back from this file to detect a stale
      # launcher, and `%h` would not resolve there.
      Environment = [ "T3CODE_HOME=${t3Home}" ];
      ExecStart = "${lib.getExe' t3codePkg "t3"} serve --host 127.0.0.1 --port 3773";
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
