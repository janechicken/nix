# Home Manager module for Hyprland (0.57+ Lua config) matching the AwesomeWM
# look & feel (dotfiles/awesome/rc.lua + mytheme.lua + picom.conf + rofi/simple.rasi):
#   - Pure #000000 OLED wallpaper, #111111 surfaces, #875fff purple focus, #d7ff5f urgent
#   - Subtle 6px rounding + crisp 150-180 ms micro-animations (`speed` is in
#     deciseconds); blur stays off (OLED power) and the wallpaper stays #000000
#   - 3px borders, 5px inner / 10px outer gaps, subtle shadows
#   - Top Waybar mirroring Awesome's wibar (tags 1-9, layout box, tasklist,
#     tray, net, battery, mem, clock); the tasklist is a socket2-driven
#     `cffi/taskbar` (focused workspace only, visible *and* minimized windows,
#     width-bounded) and the layout box a clickable `custom/layout`
#     (`[master]` / `[dwindle]`); the battery is a long-running `custom/battery`
#     script that reports the charging protocol (`PD` / `PPS` / `QC` / `AC` /
#     `USB` / `WLS`) next to a Nerd Font level ramp, on any laptop, and hides
#     itself when the machine has no battery
#   - AwesomeWM keybinds, master (tile, default) <-> dwindle (spiral) toggle, sloppy focus
#   - One independent 1-9 workspace block per configured monitor (1-9 on the
#     first, 10-18 on the second, ...) so the two monitors' workspaces are
#     *not* linked: SUPER+1..9, SUPER+Left/Right and the Waybar scroll switch a
#     workspace on the focused monitor only (`on_current_monitor = true`, i.e.
#     Hyprland's `focusworkspaceoncurrentmonitor`), the other monitor keeps its
#     workspace, and every bar relabels its own block back to 1-9;
#     `primaryMonitor` owns the cursor at startup (`cursor.default_monitor`) and
#     is XWayland's `xrandr --primary`
#   - grim + slurp + satty screenshots (Print = monitor, CTRL+Print = region,
#     SHIFT+Print = monitor straight into satty)
#   - hyprbars titlebars on floating windows only (AwesomeWM draws them on floats)
#   - Window minimize/restore via the hidden special:minimized workspace, tagged
#     per originating workspace (`minimized-ws-<N>`) so the taskbar can list a
#     workspace's minimized windows; keyboard + mouse resizing (resizeactive on
#     tiled and floating windows)
#   - Swaync notifications + control center (its `swaync-client -swb` state drives
#     the Waybar bell), SwayOSD volume/brightness/caps-lock OSD, Hyprsunset night
#     light (automatic 18:00-08:00), Hyprlock (#000000 + U2F), Hypridle lid/sleep lock
#
# Shared by every Hyprland host (hosts/<host>/home.nix). Hosts configure
# `custom.hyprland.*`; everything else (keybinds, Waybar, Swaync, Hyprlock) is
# byte-identical so the two machines look and behave the same. Only these
# hardware facts differ:
#   monitors / primaryMonitor / isLaptop / batteryName / vrr / idleLockTimeout /
#   idleDpmsTimeout
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.custom.hyprland;

  # Workspaces per monitor, matching AwesomeWM's tags 1-9. Every configured
  # monitor owns its own block of this size (1-9, 10-18, ...), bound with
  # `hl.workspace_rule` and relabelled 1-9 per bar.
  workspaceCount = 9;

  # Monitors listed in `custom.hyprland.monitors`. They own the low workspace
  # blocks (1-9, 10-18, ...); a hot-plugged output that is not configured gets
  # a block *after* them (see `focused_base` below), so it can never share an id
  # with a configured monitor's block - a shared id is exactly what made one
  # monitor switch when the other one was asked for its workspace.
  configuredMonitorCount = builtins.length cfg.monitors;

  # Volume (PipeWire/WirePlumber) with a SwayOSD progress bar. `wpctl` keeps the
  # 100 % cap (`-l 1`) and the OSD is a layer surface, so volume changes never
  # touch the notification daemon (`swaync`). `swayosd-client --output-volume`
  # would go through libpulse and bypass the cap, hence the explicit
  # `--custom-progress` path.
  volumeScript = pkgs.writeShellScript "hypr-volume" ''
    set -euo pipefail
    action="''${1:-}"
    case "$action" in
      up)
        ${pkgs.wireplumber}/bin/wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+
        ;;
      down)
        ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
        ;;
      mute)
        ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
        ;;
      *)
        exit 1
        ;;
    esac

    out="$(${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SINK@)"
    pct="$(echo "$out" | awk '{ printf "%d", ($2 * 100) + 0.5 }')"
    if echo "$out" | grep -q '\[MUTED\]'; then
      icon="audio-volume-muted-symbolic"
      text="MUTE"
    elif [ "$pct" -ge 60 ]; then
      icon="audio-volume-high-symbolic"
      text="''${pct}%"
    elif [ "$pct" -ge 25 ]; then
      icon="audio-volume-medium-symbolic"
      text="''${pct}%"
    else
      icon="audio-volume-low-symbolic"
      text="''${pct}%"
    fi

    exec ${pkgs.swayosd}/bin/swayosd-client \
      --custom-icon "$icon" \
      --custom-progress "$(awk -v p="$pct" 'BEGIN { printf "%.2f", p / 100 }')" \
      --custom-progress-text "$text"
  '';

  # Microphone mute (`XF86AudioMicMute`). All mic input runs through
  # EasyEffects, so `easyeffects_source` is the default source, but muting that
  # node does nothing audible: it is a `support.null-audio-sink` whose monitor
  # ports (the ones clients capture from) bypass the node's own volume/mute
  # (`monitor.channel-volumes = false`, `monitorMute = false`). Captured level
  # stays unchanged while the node reports `[MUTED]`. The mute has to land on
  # the hardware source EasyEffects captures from (`alsa_input.*`), which does
  # silence the whole chain down to a captured RMS of 0. Explicit
  # `set-mute 0|1` (never `toggle`) keeps every node in step; the virtual node
  # is mirrored too, purely so pavucontrol shows the state. `swayosd-client
  # --input-volume` is avoided on purpose: it goes through libpulse and would
  # toggle `@DEFAULT_AUDIO_SOURCE@` a second time.
  micMuteScript = pkgs.writeShellApplication {
    name = "hypr-mic-mute";
    runtimeInputs = [
      pkgs.jq
      pkgs.pipewire
      pkgs.swayosd
      pkgs.wireplumber
    ];
    text = ''
      dump="$(pw-dump)"

      # Hardware capture nodes: `Audio/Source` minus the virtual EasyEffects
      # node, each with its current mute state.
      hw="$(jq -r '
        .[]
        | select(.type == "PipeWire:Interface:Node")
        | select((.info.props."media.class" // "") == "Audio/Source")
        | select(((.info.props."node.virtual" // false) | tostring) != "true")
        | "\(.id) \(if (.info.params.Props[0].mute // false) then 1 else 0 end)"
      ' <<<"$dump")"

      ee="$(jq -r '
        first(.[]
          | select(.type == "PipeWire:Interface:Node")
          | select((.info.props."node.name" // "") == "easyeffects_source")
          | .id) // empty
      ' <<<"$dump")"

      ids=()
      muted=0
      while read -r id is_muted; do
        [ -n "$id" ] || continue
        ids+=("$id")
        muted=$((muted + is_muted))
      done <<<"$hw"

      if [ "''${#ids[@]}" -eq 0 ]; then
        # PipeWire restarting or no capture device at all: plain default toggle.
        wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
      else
        # One press always silences the mic: only unmute when every hardware
        # source is already muted. Every source is muted, not just the active
        # one, so a headset mic cannot stay live behind the built-in one.
        if [ "$muted" -eq "''${#ids[@]}" ]; then
          state=0
        else
          state=1
        fi
        for id in "''${ids[@]}"; do
          wpctl set-mute "$id" "$state"
        done
        if [ -n "$ee" ]; then
          wpctl set-mute "$ee" "$state"
        fi
      fi

      # Read back from the default source (the mirrored virtual node, or the
      # hardware source when EasyEffects is not running) for the OSD.
      if wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | grep -q '\[MUTED\]'; then
        icon="microphone-sensitivity-muted-symbolic"
        text="MUTED"
        progress="0.00"
      else
        icon="microphone-sensitivity-high-symbolic"
        text="ON"
        progress="1.00"
      fi

      exec swayosd-client \
        --custom-icon "$icon" \
        --custom-progress "$progress" \
        --custom-progress-text "$text"
    '';
  };

  # Right click on the Waybar bluetooth module: toggle the adapter's power.
  # `bluetoothctl show` fails (no controller -> nothing printed) on machines
  # without a Bluetooth adapter, so the script then just tries `power on`.
  bluetoothToggleScript = pkgs.writeShellScript "waybar-bluetooth-toggle" ''
    set -euo pipefail
    ctl=${pkgs.bluez}/bin/bluetoothctl
    if $ctl show 2>/dev/null | grep -q 'Powered: yes'; then
      $ctl power off >/dev/null
    else
      $ctl power on >/dev/null
    fi
  '';

  # Panel backlight with a SwayOSD progress bar. The ATNA40CT03-0 OLED eDP
  # backlight must NEVER reach 0 %: `-n5%` floors every step at 5 %, and the OSD
  # reports the percentage brightnessctl actually clamped to.
  brightnessScript = pkgs.writeShellScript "hypr-brightness" ''
    set -euo pipefail
    action="''${1:-}"
    case "$action" in
      up)
        ${pkgs.brightnessctl}/bin/brightnessctl -e4 -n5% set 5%+ >/dev/null
        ;;
      down)
        ${pkgs.brightnessctl}/bin/brightnessctl -e4 -n5% set 5%- >/dev/null
        ;;
      *)
        exit 1
        ;;
    esac

    pct="$(${pkgs.brightnessctl}/bin/brightnessctl -m | cut -d, -f4 | tr -d '%')"

    exec ${pkgs.swayosd}/bin/swayosd-client \
      --custom-icon display-brightness-symbolic \
      --custom-progress "$(awk -v p="$pct" 'BEGIN { printf "%.2f", p / 100 }')" \
      --custom-progress-text "''${pct}%"
  '';

  # Night light quick toggle (Swaync's "Night Light" button). Hyprsunset's own
  # IPC answers the state query: `hyprctl hyprsunset identity get` prints
  # "true" while the matrix is neutral, "false" while a temperature is applied.
  # `status` feeds Swaync's `update-command` (warm == toggle active).
  nightLightScript = pkgs.writeShellScript "hypr-night-light" ''
    set -euo pipefail
    hyprctl=${pkgs.hyprland}/bin/hyprctl
    case "''${1:-toggle}" in
      status)
        if [ "$($hyprctl hyprsunset identity get 2>/dev/null)" = "true" ]; then
          echo false
        else
          echo true
        fi
        ;;
      toggle)
        if [ "$($hyprctl hyprsunset identity get 2>/dev/null)" = "true" ]; then
          $hyprctl hyprsunset temperature 4000 >/dev/null
        else
          $hyprctl hyprsunset identity true >/dev/null
        fi
        ;;
      *)
        exit 1
        ;;
    esac
  '';

  # Screenshots: grim captures, satty annotates. `monitor` is the instant
  # AwesomeWM-style Print (capture the focused output, copy it, notify), the two
  # editing modes pipe grim straight into satty, which copies on Enter and saves
  # through its own `output-filename` (see the satty config.toml below).
  screenshotScript = pkgs.writeShellApplication {
    name = "hypr-screenshot";
    runtimeInputs = [
      pkgs.grim
      pkgs.slurp
      pkgs.satty
      pkgs.wl-clipboard
      pkgs.libnotify
      pkgs.jq
      pkgs.hyprland
    ];
    text = ''
      action="''${1:-monitor}"
      dir="$HOME/Pictures/Screenshots"
      mkdir -p "$dir"

      # The focused output's name, straight from Hyprland's IPC (`monitors` is a
      # JSON array with exactly one `focused: true` entry).
      focused_output() {
        hyprctl -j monitors | jq -r '.[] | select(.focused) | .name'
      }

      case "$action" in
        monitor)
          file="$dir/$(date +%Y-%m-%d_%H:%M:%S).png"
          grim -o "$(focused_output)" "$file"
          wl-copy < "$file"
          notify-send -i "$file" "Screenshot saved" "$file"
          ;;
        region)
          # slurp exits non-zero when the selection is cancelled (Escape).
          geom="$(slurp)" || exit 0
          [ -n "$geom" ] || exit 0
          grim -g "$geom" - | satty -f -
          ;;
        monitor-edit)
          grim -o "$(focused_output)" - | satty -f -
          ;;
        *)
          echo "usage: $0 {monitor|region|monitor-edit}" >&2
          exit 1
          ;;
      esac
    '';
  };

  # `cursor.default_monitor` (Hyprland 0.57.2 config key `cursor:default_monitor`,
  # "the name of a default monitor for the cursor to be set to on startup") and
  # the matching `xrandr --primary` for XWayland. Both are single-line Lua
  # fragments on purpose: a multi-line `${...}` interpolation inside the Lua
  # template loses its indentation, a single line keeps the template's own.
  primaryMonitorCursorLua = lib.optionalString (cfg.primaryMonitor != null) (
    "cursor = { default_monitor = ${luaScalar cfg.primaryMonitor} }, -- start the pointer on the primary output"
  );

  primaryMonitorXrandrLua = lib.optionalString (cfg.primaryMonitor != null) (
    ''hl.exec_cmd("${pkgs.xrandr}/bin/xrandr --output ${cfg.primaryMonitor} --primary") -- also primary for XWayland''
  );

  # SwayOSD stylesheet (AwesomeWM palette, 6px corners, purple progress).
  swayosdStyle = pkgs.writeText "swayosd-style.css" ''
    window#osd {
      border-radius: 6px;
      border: 1px solid #875fff;
      background: #111111;
    }

    window#osd #container {
      margin: 10px 14px;
    }

    window#osd image,
    window#osd label {
      color: #ffffff;
    }

    window#osd progressbar,
    window#osd segmentedprogress {
      min-height: 6px;
      border-radius: 6px;
      border: none;
      background: transparent;
    }

    window#osd trough,
    window#osd segment {
      min-height: inherit;
      border-radius: inherit;
      border: none;
      background: #2a2a2a;
    }

    window#osd progress,
    window#osd segment.active {
      min-height: inherit;
      border-radius: inherit;
      border: none;
      background: #875fff;
    }
  '';

  # Waybar active-workspace taskbar (CFFI GTK3 module): Waybar 0.16's built-in
  # wlr/taskbar cannot filter by Hyprland workspace, while custom/* modules
  # cannot render real per-app GTK icons. This small CFFI shared library listens
  # on Hyprland's `.socket2.sock` (no polling), shows only mapped windows on the
  # focused workspace with their real .desktop / icon-theme app icons, focuses a
  # window on click, and caps its own width from the monitor's logical width so
  # workspaces and tray/clock can never be pushed off-screen.
  waybarHyprTaskbar = pkgs.callPackage ../pkgs/waybar-hypr-taskbar { };

  # Waybar layout indicator: `[master]` / `[dwindle]` next to the workspaces,
  # `toggle` flips the layout and re-runs every `signal = 8` Waybar module.
  layoutScript = pkgs.writers.writePython3 "hypr-layout" { } ''
    """Waybar layout indicator for Hyprland 0.57 (Lua config).

    `hypr-layout` prints the active workspace's tiling layout as Waybar JSON
    (`[master]` / `[dwindle]`); `hypr-layout toggle` flips master <-> dwindle and
    re-runs every `signal = 8` Waybar module (SIGRTMIN+8) so the label updates
    instantly. Also invoked by the SUPER+Space bind in hyprland.lua.
    """

    import json
    import os
    import socket
    import subprocess
    import sys

    SIGNAL = "RTMIN+8"
    PKILL = "${pkgs.procps}/bin/pkill"


    def socket_path():
        runtime = os.environ.get("XDG_RUNTIME_DIR") or "/run/user/%d" % os.getuid()
        base = os.path.join(runtime, "hypr")
        sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
        if sig:
            return os.path.join(base, sig, ".socket.sock")
        try:
            candidates = [os.path.join(base, e) for e in os.listdir(base)]
        except OSError:
            candidates = []
        candidates = [c for c in candidates if os.path.isdir(c)]
        if not candidates:
            return os.path.join(base, "missing", ".socket.sock")
        return os.path.join(max(candidates, key=os.path.getmtime), ".socket.sock")


    def request(command):
        """One request/response round trip on the Hyprland command socket."""
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(2.0)
        try:
            sock.connect(socket_path())
            sock.sendall(command.encode("utf-8", "replace"))
            chunks = []
            while True:
                chunk = sock.recv(65536)
                if not chunk:
                    break
                chunks.append(chunk)
            return b"".join(chunks).decode("utf-8", "replace").strip()
        finally:
            sock.close()


    def current_layout():
        try:
            workspace = json.loads(request("j/activeworkspace"))
            layout = workspace.get("tiledLayout") or workspace.get("tiled_layout")
            if layout:
                return layout
        except Exception:  # noqa: BLE001 - fall through to the option query
            pass
        try:
            option = json.loads(request("j/getoption general:layout"))
            return option.get("str") or "master"
        except Exception:  # noqa: BLE001
            return "master"


    def set_layout(layout):
        request('eval hl.config({ general = { layout = "%s" } })' % layout)


    def refresh_bar():
        subprocess.run([PKILL, "-" + SIGNAL, "waybar"], check=False)


    def main(argv):
        if len(argv) > 1 and argv[1] == "toggle":
            layout = current_layout()
            set_layout("master" if layout == "dwindle" else "dwindle")
            refresh_bar()
            return 0

        layout = current_layout()
        other = "dwindle" if layout == "master" else "master"
        tooltip = "Layout: %s\nClick: switch to %s\nSUPER+Space: toggle" % (
            layout,
            other,
        )
        sys.stdout.write(
            json.dumps(
                {
                    "text": "[%s]" % layout,
                    "tooltip": tooltip,
                    "class": layout,
                    "alt": layout,
                }
            )
            + "\n"
        )
        sys.stdout.flush()
        return 0


    if __name__ == "__main__":
        try:
            sys.exit(main(sys.argv))
        except (BrokenPipeError, KeyboardInterrupt):
            sys.exit(0)
  '';

  # Waybar battery module (`custom/battery`): one self-contained Python script
  # (stdlib only) that auto-discovers every `/sys/class/power_supply` device, so
  # the same code drives `BAT0`/`AC`/`ucsi-source-psy-*` on an Intel/AMD laptop
  # and `qcom-battmgr-{bat,ac,usb,wls}` + `ucsi-source-psy-pmic_glink.ucsi.*` on
  # the Snapdragon X2 - no hardcoded sysfs names. It replaces Waybar's built-in
  # `battery` module, which cannot report the charging protocol. Bar text below;
  # the leading glyph is the Material Design battery / charging-battery ramp,
  # elided here for readability:
  #
  #   [ 59% 16.5W 2h30m] discharging: ramp + level + live draw + runtime left
  #   [ 59% 16.5W]       ... runtime unknown, or draw below 0.05 W (no `0.0W`)
  #   [PD 59% +18.2W 1h12m] USB-PD, >= 5.5 V or >= 15 W  (class: fast-charging)
  #   [PPS 59% +30.1W 42m]  USB-PD PPS                   (class: fast-charging)
  #   [PD5 59% +7.5W]   USB-PD negotiated at 5 V (slow charger)
  #   [QC 59% +15.0W]   Quick Charge / vendor fast charge, non-PD
  #   [AC 59% +45.0W]   mains / DCP / CDP wall charger
  #   [USB 59% +2.5W]   SDP or plain 5 V USB port (slow)
  #   [WLS 59% +5.0W]   wireless charging
  #   [ PD 100%] plugged in, full   /  [ 80%] plugged in, not charging
  #   (watts are the battery's own draw; the time-to-full part only appears
  #   while charging and when the estimate is plausible)
  #
  # Tooltip: status, protocol (incl. PD revision + PPS capability), charger V/A
  # and negotiated watts, battery power, time to full/empty, health, cycles,
  # temperature and the charge threshold. No battery (desktop) -> empty `text`,
  # which Waybar 0.16 hides (`hide-empty-text`).
  #
  # It is a *streaming* producer, not a polled one: Waybar starts it once and
  # reads JSON lines from its stdout (no `interval`, so no re-exec every tick
  # and no timer wakeup). The script prints the initial line immediately, then
  # blocks in `select` on a `NETLINK_KOBJECT_UEVENT` socket (group 1), waking
  # only on a `power_supply` uevent (plug/unplug, capacity, PD negotiation) or
  # a 15 s heartbeat, and re-emits only when the JSON actually changed. Zero
  # subprocesses, zero dependencies beyond the stdlib. With no battery it
  # prints the empty line once and exits, so a desktop idles nothing at all.
  # `--once` prints a single line and exits (tests, `waybar-battery` by hand).
  batteryScript = pkgs.writers.writePython3 "waybar-battery" { } ''
    """Waybar battery indicator (`custom/battery`) for the Hyprland bar.

    Discovery is name-agnostic: every `/sys/class/power_supply` device is
    inspected, so the same script drives `BAT0` + `AC` + `ucsi-source-psy-*` on an
    Intel/AMD laptop and `qcom-battmgr-{bat,ac,usb,wls}` +
    `ucsi-source-psy-pmic_glink.ucsi.*` on the Snapdragon X2. No battery -> empty
    `text`, which Waybar 0.16 hides (`hide-empty-text` / empty formatted text).

    Bar text (`[...]` matches the rest of the bar):
        [ 59% 16.5W 2h30m]  discharging: Nerd Font battery ramp glyph,
                      capacity, live draw in watts and the remaining runtime
                      (`42m` below 1 h). Each part is dropped when unknown, and
                      a draw under 0.05 W is not shown (no bogus `0.0W`).
        [PD 59% +18.2W 1h12m]  USB-PD charging, >= 5.5 V or >= 15 W (fast):
                      charging ramp glyph, protocol tag, capacity, signed draw
                      and time to full
        [PPS 59% +30.1W 42m]   USB-PD PPS charging (fast)
        [PD5 59% +7.5W]       USB-PD at 5 V (slow charger)
        [QC 59% +15.0W]       Quick Charge / vendor fast charge (non-PD)
        [AC 59% +45.0W]       mains / DCP / CDP wall charger
        [USB 59% +2.5W]       SDP / plain 5 V USB port (slow)
        [WLS 59% +5.0W]       wireless charging
        [ PD 100%]            plugged in, full (tag = negotiated protocol)
        [ 80%]                plugged in, not charging (charge threshold)

    Watts come from the battery's own `power_now` (microwatts), falling back to
    `current_now` * `voltage_now` (microamps * microvolts / 1e12) when the driver
    reports no power; the absolute value is used because several drivers report
    a negative current while discharging.

    `BATTERY_SYSFS_ROOT` (default `/sys/class`) points discovery at another tree;
    that is how the mock-sysfs tests exercise every branch.

    Waybar runs the script once, as a streaming JSON producer: the first line
    is printed immediately, then the process sleeps in `select` on a
    `NETLINK_KOBJECT_UEVENT` socket and re-reads sysfs only on a
    `SUBSYSTEM=power_supply` uevent (debounced, so a plug/unplug burst is read
    once, settled) or on a 15 s heartbeat for the time-based numbers. A line is
    printed only when it changed. No battery -> the empty line is printed once
    and the process exits 0, so a desktop keeps no idle daemon. `--once`
    prints a single line and exits.
    """

    import json
    import os
    import re
    import select
    import signal
    import socket
    import sys
    import time
    import traceback

    # Discovery roots (see module docstring).
    SYSFS_ROOT = os.environ.get("BATTERY_SYSFS_ROOT") or "/sys/class"
    POWER_SUPPLY = os.path.join(SYSFS_ROOT, "power_supply")
    TYPEC = os.path.join(SYSFS_ROOT, "typec")

    # Optional preferred battery name (`custom.hyprland.batteryName`). Discovery
    # still works when the name is wrong or absent.
    PREFERRED_BATTERY = ${if cfg.batteryName == null then "None" else builtins.toJSON cfg.batteryName}

    # Nerd Font Material Design glyphs (present in JetBrainsMono Nerd Font 3.5.0).
    DISCHARGE_GLYPHS = {
        "outline": "\U000f008e",  # md-battery_outline
        "10": "\U000f007a",  # md-battery_10
        "20": "\U000f007b",
        "30": "\U000f007c",
        "40": "\U000f007d",
        "50": "\U000f007e",
        "60": "\U000f007f",
        "70": "\U000f0080",
        "80": "\U000f0081",
        "90": "\U000f0082",
        "full": "\U000f0079",  # md-battery
    }
    # Material Design only ships a charging ramp at 20/30/40/60/80/90/100.
    CHARGE_GLYPHS = {
        "20": "\U000f0086",  # md-battery_charging_20
        "30": "\U000f0087",
        "40": "\U000f0088",
        "60": "\U000f0089",
        "80": "\U000f008a",
        "90": "\U000f008b",
        "100": "\U000f0085",  # md-battery_charging_100
    }
    PLUG_GLYPH = "\uf1e6"  # fa-plug

    PROTO_RANK = {"PPS": 6, "PD": 5, "QC": 4, "AC": 3, "USB": 2, "WLS": 1}
    PROTO_NAMES = {
        "PPS": "USB-PD PPS",
        "PD": "USB-PD",
        "QC": "Quick Charge",
        "AC": "mains",
        "USB": "USB",
        "WLS": "wireless",
    }
    FAST_PROTOCOLS = ("PPS", "PD", "QC")
    FAST_POWER_W = 15.0
    FAST_VOLTAGE_V = 5.5

    INT_KEYS = (
        "online",
        "present",
        "capacity",
        "voltage_now",
        "voltage_max",
        "voltage_min",
        "voltage_max_design",
        "current_now",
        "current_max",
        "power_now",
        "energy_now",
        "energy_full",
        "energy_full_design",
        "charge_now",
        "charge_full",
        "charge_full_design",
        "cycle_count",
        "temp",
        "charge_control_end_threshold",
    )
    STR_KEYS = ("type", "scope", "status", "usb_type", "charge_type", "model_name")
    BRACKET = re.compile(r"\[([^\]]+)\]")


    def read(path):
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as handle:
                return handle.read().strip()
        except OSError:
            return ""


    def read_int(path):
        try:
            return int(read(path))
        except ValueError:
            return None


    def read_supply(path):
        supply = {"path": path, "name": os.path.basename(path)}
        for key in INT_KEYS:
            supply[key] = read_int(os.path.join(path, key))
        for key in STR_KEYS:
            supply[key] = read(os.path.join(path, key))
        return supply


    def all_supplies():
        try:
            names = sorted(os.listdir(POWER_SUPPLY))
        except OSError:
            return []
        return [
            read_supply(os.path.join(POWER_SUPPLY, name))
            for name in names
            if os.path.isdir(os.path.join(POWER_SUPPLY, name))
        ]


    def pick_battery(supplies):
        """The system battery: `type == Battery`, `scope != Device`, present."""
        candidates = [
            s
            for s in supplies
            if s["type"] == "Battery" and s["scope"] != "Device"
        ]
        present = [
            s for s in candidates if s["present"] is None or s["present"] != 0
        ]
        if not present:
            return None
        if PREFERRED_BATTERY:
            for supply in present:
                if supply["name"] == PREFERRED_BATTERY:
                    return supply
        return max(present, key=lambda s: s["energy_now"] or s["charge_now"] or 0)


    def parse_usb_type(value):
        """`C [PD] PD_PPS` -> active `PD`, supported [C, PD, PD_PPS]."""
        value = value or ""
        match = BRACKET.search(value)
        active = match.group(1).strip() if match else ""
        supported = value.replace("[", " ").replace("]", " ").split()
        return active, supported


    def supply_protocol(supply):
        """Charging protocol reported by one (online) supply, or None."""
        active, _supported = parse_usb_type(supply["usb_type"])
        if active.startswith("PD_PPS"):
            return "PPS"
        if active.startswith("PD"):
            return "PD"
        if active.startswith("QC"):
            return "QC"
        if active in ("DCP", "CDP", "ACA"):
            return "AC"
        if active in ("C", "SDP"):
            return "USB"

        charge_type = (supply["charge_type"] or "").lower()
        if charge_type == "fast":
            return "QC"

        kind = (supply["type"] or "").lower()
        if kind == "wireless":
            return "WLS"
        if kind in ("mains", "usb_c"):
            return "AC"
        if kind == "usb" and charge_type in (
            "standard",
            "adaptive",
            "slow",
            "trickle",
        ):
            return "USB"
        return None


    def typec_pd():
        """Type-C PD facts for the port currently acting as a PD sink."""
        info = {"pd": False, "revision": None, "partner": None}
        try:
            names = sorted(os.listdir(TYPEC))
        except OSError:
            return info
        for name in names:
            path = os.path.join(TYPEC, name)
            if (
                not name.startswith("port")
                or name.endswith("-partner")
                or not os.path.isdir(path)
            ):
                continue
            mode = read(os.path.join(path, "power_operation_mode"))
            role = read(os.path.join(path, "power_role"))
            if mode != "usb_power_delivery" or "[sink]" not in role:
                continue
            info["pd"] = True
            info["revision"] = (
                read(os.path.join(path, "usb_power_delivery_revision")) or None
            )
            partner = path + "-partner"
            if os.path.isdir(partner):
                supports = read(
                    os.path.join(partner, "supports_usb_power_delivery")
                )
                if supports == "yes":
                    info["partner"] = (
                        read(os.path.join(partner, "usb_power_delivery_revision"))
                        or "yes"
                    )
        return info


    def first_positive(supply, keys):
        for key in keys:
            value = supply[key]
            if value is not None and value > 0:
                return value
        return None


    def supply_voltage(supply):
        return first_positive(supply, ("voltage_now", "voltage_max"))


    def supply_current(supply):
        return first_positive(supply, ("current_now", "current_max"))


    def supply_power(supply):
        """Negotiated charger power in microwatts (0 when the driver hides it)."""
        voltage = supply_voltage(supply)
        current = supply_current(supply)
        if voltage and current:
            return voltage * current / 1e6
        return first_positive(supply, ("power_now",))


    def battery_power_uw(battery):
        """Battery draw in microwatts (signed), `power_now` or I*V fallback."""
        if battery["power_now"] is not None:
            return battery["power_now"]
        current = battery["current_now"]
        voltage = first_positive(
            battery, ("voltage_now", "voltage_min", "voltage_max_design")
        )
        if current is not None and voltage:
            # uA * uV = pW, so / 1e6 lands on microwatts.
            return current * voltage / 1e6
        return None


    def capacity_of(battery):
        if battery["capacity"] is not None:
            return max(0, min(100, battery["capacity"]))
        pairs = (("energy_now", "energy_full"), ("charge_now", "charge_full"))
        for now, full in pairs:
            if battery[now] and battery[full]:
                percent = int(round(100.0 * battery[now] / battery[full]))
                return max(0, min(100, percent))
        return None


    def energy_state(battery):
        """(now, full, unit, now_wh, full_wh); Wh is None without a voltage."""
        if battery["energy_now"] and battery["energy_full"]:
            now = battery["energy_now"] / 1e6
            full = battery["energy_full"] / 1e6
            return now, full, "Wh", now, full
        if battery["charge_now"] and battery["charge_full"]:
            now = battery["charge_now"] / 1e6
            full = battery["charge_full"] / 1e6
            volts = first_positive(
                battery, ("voltage_now", "voltage_min", "voltage_max_design")
            )
            if volts:
                return now, full, "Ah", now * volts / 1e6, full * volts / 1e6
            return now, full, "Ah", None, None
        return None, None, None, None, None


    def discharge_glyph(capacity):
        if capacity is None or capacity <= 5:
            return DISCHARGE_GLYPHS["outline"]
        if capacity >= 96:
            return DISCHARGE_GLYPHS["full"]
        bucket = max(10, min(90, int(capacity / 10.0 + 0.5) * 10))
        return DISCHARGE_GLYPHS[str(bucket)]


    def charge_glyph(capacity):
        if capacity is None or capacity <= 25:
            return CHARGE_GLYPHS["20"]
        if capacity <= 35:
            return CHARGE_GLYPHS["30"]
        if capacity <= 45:
            return CHARGE_GLYPHS["40"]
        if capacity <= 70:
            return CHARGE_GLYPHS["60"]
        if capacity <= 85:
            return CHARGE_GLYPHS["80"]
        if capacity <= 95:
            return CHARGE_GLYPHS["90"]
        return CHARGE_GLYPHS["100"]


    def fmt_power(microwatts, charging):
        """Tooltip watts: `-16.5 W` / `+18.2 W`; None when 0 or unavailable."""
        if microwatts is None:
            return None
        watts = abs(microwatts) / 1e6
        if watts < 0.05:
            return None
        return "%s%.1f W" % ("+" if charging else "-", watts)


    def fmt_watts(microwatts, charging):
        """Compact bar watts: `6.4W`, `+18.2W`; None when 0 or unavailable."""
        if microwatts is None:
            return None
        watts = abs(microwatts) / 1e6
        if watts < 0.05:
            return None
        return "%s%.1fW" % ("+" if charging else "", watts)


    def fmt_duration(seconds):
        seconds = int(round(seconds))
        if seconds < 60:
            return "less than a minute"
        hours, remainder = divmod(seconds, 3600)
        minutes = remainder // 60
        if hours:
            return "%dh %02dm" % (hours, minutes)
        return "%dm" % minutes


    def fmt_eta(seconds):
        """Compact runtime for the bar: `3h5m`, `3h` or `42m`."""
        minutes = int(round(seconds / 60.0))
        hours, minutes = divmod(minutes, 60)
        if hours and minutes:
            return "%dh%dm" % (hours, minutes)
        if hours:
            return "%dh" % hours
        return "%dm" % minutes


    def fmt_float(value, digits=2):
        return ("%." + str(digits) + "f") % value


    def classify(supplies):
        """Full display model, or None when the machine has no battery."""
        battery = pick_battery(supplies)
        if battery is None:
            return None

        status = battery["status"] or "Unknown"
        capacity = capacity_of(battery)
        charging = status.lower() == "charging"
        online = [s for s in supplies if s["online"] == 1]
        typec = typec_pd()

        best_rank = 0
        proto = None
        best_supply = None
        for supply in online:
            candidate = supply_protocol(supply)
            if candidate is None:
                continue
            rank = PROTO_RANK[candidate]
            if rank > best_rank:
                best_rank, proto, best_supply = rank, candidate, supply
        if proto is None and typec["pd"] and (online or charging):
            proto = "PD"

        plugged = bool(online) or status.lower() in (
            "charging",
            "full",
            "not charging",
        )

        voltage = supply_voltage(best_supply) if best_supply else None
        current = supply_current(best_supply) if best_supply else None
        if voltage is None:
            for supply in online:
                voltage = supply_voltage(supply)
                if voltage:
                    break
        if current is None:
            for supply in online:
                current = supply_current(supply)
                if current:
                    break
        charger_power = supply_power(best_supply) if best_supply else None
        if charger_power is None and voltage and current:
            charger_power = voltage * current

        battery_power = battery_power_uw(battery)
        now, full, unit, now_wh, full_wh = energy_state(battery)
        rate = abs(battery_power) / 1e6 if battery_power else 0.0
        # Remaining runtime on battery, appended to the bar text as `3h5m`.
        # Only while discharging (charging/plugged/unknown -> no clutter) and
        # only for a plausible draw (0.5 W .. 100 h); the tooltip carries the
        # long form either way.
        eta = ""
        if not charging and not plugged and rate > 0.5 and now_wh:
            hours = now_wh / rate
            if 0 < hours < 100:
                eta = fmt_eta(hours * 3600)

        fast = False
        if charging:
            if proto in ("PPS", "QC", "AC"):
                fast = True
            elif proto == "PD":
                fast = bool(
                    (voltage and voltage > FAST_VOLTAGE_V * 1e6)
                    or (charger_power and charger_power >= FAST_POWER_W * 1e6)
                    or (battery_power and abs(battery_power) >= FAST_POWER_W * 1e6)
                )

        slow_pd = bool(charging and proto == "PD" and not fast)
        tag = ""
        if proto == "PD":
            tag = "PD5" if slow_pd else "PD"
        elif proto is not None:
            tag = proto

        if capacity is None:
            percent = ""
        else:
            percent = "%d%%" % capacity

        # Live draw in the bar, but only while the pack is actually moving
        # charge: `full` / `not charging` would only ever print a bogus 0.0 W.
        watts = ""
        if charging or not plugged:
            watts = fmt_watts(battery_power, charging) or ""

        # Time to full while charging, same compact `3h5m` shape as the ETA.
        fill = ""
        if charging and rate > 0.5 and now_wh is not None and full_wh is not None:
            hours = (full_wh - now_wh) / rate
            if 0 < hours < 100:
                fill = fmt_eta(hours * 3600)

        if charging:
            head = charge_glyph(capacity) + tag
        elif plugged:
            head = PLUG_GLYPH + tag
        else:
            head = discharge_glyph(capacity)
        text = "[%s]" % " ".join(
            part for part in (head, percent, watts, eta, fill) if part
        )

        classes = []
        if charging:
            classes.append("charging")
        if fast:
            classes.append("fast-charging")
        if proto == "PPS":
            classes.extend(["pd", "pps"])
        elif proto == "PD":
            classes.append("pd")
        elif proto == "QC":
            classes.append("qc")
        elif proto == "WLS":
            classes.append("wireless")
        elif proto == "AC":
            classes.append("ac")
        if plugged and not charging:
            classes.append("plugged")
        if status.lower() == "full":
            classes.append("full")
        if not plugged and capacity is not None:
            if capacity <= 25:
                classes.append("warning")
            if capacity <= 15:
                classes.append("critical")

        # ---- tooltip -----------------------------------------------------------
        lines = []
        if proto is not None:
            supply_type = best_supply["type"] if best_supply is not None else ""
            active, supported = ("", [])
            if best_supply is not None:
                active, supported = parse_usb_type(best_supply["usb_type"])
            label = PROTO_NAMES[proto]
            if proto == "AC":
                label = "mains" if supply_type == "Mains" else "USB charger"
            if proto == "PD" and typec["revision"]:
                label += " %s" % typec["revision"]
            notes = []
            if proto in ("PD", "PPS") and "PD_PPS" in supported and proto != "PPS":
                notes.append("PPS capable")
            if slow_pd:
                notes.append("5 V, slow")
            if active and proto in ("AC", "USB"):
                notes.append(active)
            if notes:
                label += " (%s)" % ", ".join(notes)
            if proto == "PD" and typec["partner"]:
                label += " / partner PD %s" % typec["partner"]
            lines.append("%s \u2014 %s" % (status, label))
        else:
            lines.append(status)

        if voltage or current:
            if voltage and current:
                charger = "%s V / %s A (%s W)" % (
                    fmt_float(voltage / 1e6),
                    fmt_float(current / 1e6),
                    fmt_float(voltage * current / 1e12, 0),
                )
            elif current:
                charger = "%s A (voltage not reported)" % fmt_float(current / 1e6)
            else:
                charger = "%s V (current not reported)" % fmt_float(voltage / 1e6)
            lines.append("Charger: %s" % charger)

        power = fmt_power(battery_power, charging)
        if power:
            lines.append("Battery power: %s" % power)
        if now is not None:
            if rate > 0.5 and now_wh is not None and full_wh is not None:
                hours = None
                if charging:
                    hours = (full_wh - now_wh) / rate
                    label = "Time to full"
                elif plugged:
                    hours = None
                    label = ""
                else:
                    hours = now_wh / rate
                    label = "Time to empty"
                if hours is not None and 0 < hours < 100:
                    lines.append("%s: %s" % (label, fmt_duration(hours * 3600)))
            lines.append(
                "Battery: %s \u2014 %s / %s %s"
                % (percent or "?", fmt_float(now, 1), fmt_float(full, 1), unit)
            )

        design = battery["energy_full_design"]
        if design and full:
            health = 100.0 * full * 1e6 / design
            lines.append(
                "Health: %s%% (%s Wh design)"
                % (fmt_float(health, 0), fmt_float(design / 1e6, 1))
            )
        elif battery["charge_full_design"] and battery["charge_full"]:
            health = 100.0 * battery["charge_full"] / battery["charge_full_design"]
            design_ah = battery["charge_full_design"] / 1e6
            lines.append(
                "Health: %s%% (%s Ah design)"
                % (fmt_float(health, 0), fmt_float(design_ah, 2))
            )

        extras = []
        if battery["cycle_count"]:
            extras.append("Cycles: %d" % battery["cycle_count"])
        if battery["temp"]:
            extras.append("%s\u00b0C" % fmt_float(battery["temp"] / 10.0, 1))
        if extras:
            lines.append(" \u00b7 ".join(extras))
        if battery["charge_control_end_threshold"]:
            limit = battery["charge_control_end_threshold"]
            lines.append("Charge limit: %d%%" % limit)

        return {
            "text": text,
            "tooltip": "\n".join(lines),
            "class": classes,
            "alt": tag or status,
            "percentage": capacity if capacity is not None else 0,
        }


    # ---- streaming ---------------------------------------------------------


    EMPTY = {"text": "", "tooltip": "", "class": [], "alt": ""}
    POLL_SECONDS = 15.0
    DEBOUNCE_SECONDS = 0.15


    def snapshot():
        """(JSON line, battery present) for the current sysfs state."""
        result = classify(all_supplies())
        if result is None:
            # No battery (desktop): empty text, Waybar hides the module.
            return json.dumps(EMPTY), False
        return json.dumps(result), True


    def emit(line):
        print(line, flush=True)


    def open_uevent():
        """Non-blocking NETLINK_KOBJECT_UEVENT socket, None when unavailable."""
        try:
            proto = getattr(socket, "NETLINK_KOBJECT_UEVENT", 15)
            nl = socket.socket(socket.AF_NETLINK, socket.SOCK_DGRAM, proto)
            try:
                nl.bind((0, 1))  # group 1: kernel -> userspace uevents
                nl.setblocking(False)
            except OSError:
                nl.close()
                raise
            return nl
        except OSError:
            # No netlink here (odd kernel or sandbox): heartbeat only.
            return None


    def drain_uevents(nl):
        """Every queued uevent datagram, without blocking."""
        events = []
        while True:
            try:
                events.append(nl.recv(8192))
            except (BlockingIOError, InterruptedError):
                return events
            except OSError:
                return events


    def power_supply_ready(nl):
        """True once a `power_supply` uevent arrived; settles the burst."""
        events = drain_uevents(nl)
        if not any(b"SUBSYSTEM=power_supply" in e for e in events):
            return False
        # A plug/unplug emits a burst (one uevent per attribute that changed);
        # let the rest land so the read below sees settled sysfs rather than a
        # half-updated device, then drop them instead of redrawing per datagram.
        time.sleep(DEBOUNCE_SECONDS)
        drain_uevents(nl)
        return True


    def stream():
        """Emit on change only, waking on `power_supply` uevents."""
        line, present = snapshot()
        emit(line)
        if not present:
            # Desktop: nothing to watch, so no idle daemon and no timer.
            return 0
        last = line
        nl = open_uevent()
        while True:
            if nl is None:
                time.sleep(POLL_SECONDS)  # no uevents: heartbeat only
            else:
                try:
                    readable = select.select([nl], [], [], POLL_SECONDS)[0]
                except InterruptedError:  # a signal: re-read right away
                    readable = []
                if readable and not power_supply_ready(nl):
                    continue  # another subsystem's uevent: nothing to redraw
            line, present = snapshot()
            if line != last:
                # An unchanged line would only make Waybar repaint for nothing.
                emit(line)
                last = line
            if not present:
                return 0  # battery gone (hot-unplug): stop idling


    def main(argv):
        if "--once" in argv[1:]:
            line = snapshot()[0]
            emit(line)
            return 0
        return stream()


    def _terminate(_signum, _frame):
        """SIGTERM/SIGINT: unwind out of `select` without a traceback."""
        raise SystemExit(0)


    if __name__ == "__main__":
        code = 0
        try:
            for sig in (signal.SIGTERM, signal.SIGINT):
                signal.signal(sig, _terminate)
            code = main(sys.argv)
        except BrokenPipeError:
            # Waybar closed the pipe (bar restarted, module removed).
            code = 0
        except (KeyboardInterrupt, SystemExit):
            code = 0
        except Exception:  # noqa: BLE001 - a bar module must never crash
            traceback.print_exc()
            emit(json.dumps(EMPTY))
            code = 0
        try:
            sys.stdout.flush()
        except BrokenPipeError:
            # The documented recipe for a silent exit on a closed stdout.
            os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        sys.exit(code)
  '';

  # Waybar scroll handler: the same per-monitor wrap-around as `cycle_workspace`
  # below, evaluated by Hyprland's own Lua runtime through `hyprctl dispatch`.
  # `dispatch` wraps its argument as `return hl.dispatch(<arg>)` (Hyprland
  # 0.57.2, src/ipc/s1/Commands.cpp:dispatchRequest), so the base-offset lookup
  # has to be a single expression: an immediately invoked function.
  # `r+1`/`r-1` must never be used here: a single trackpad scroll would spawn
  # workspaces outside the focused monitor's block.
  #
  # `on_current_monitor = true` is what keeps the two monitors unlinked: without
  # it `hl.dsp.focus({ workspace = N })` is Hyprland's plain `workspace`
  # dispatcher (`Actions::changeWorkspace`), which switches N on whichever
  # monitor *owns* it and then moves keyboard focus there - i.e. asking for
  # workspace 1 while focused on the second monitor switched the first one.
  # With the flag it becomes `Actions::changeWorkspaceOnCurrentMonitor`
  # (src/config/lua/bindings/LuaBindingsDispatchers.cpp:hlFocus ->
  # src/config/shared/actions/ConfigActions.cpp), which only ever touches the
  # focused monitor.
  cycleWorkspaceCmd =
    delta:
    let
      baseTable = monitorBaseTable "'";
      d = toString delta;
      n = toString workspaceCount;
      cm = toString configuredMonitorCount;
    in
    "hyprctl dispatch \"hl.dsp.focus({workspace = (function() "
    + "local t = ${baseTable} "
    + "local m = hl.get_active_monitor() "
    + "local b = t[m and m.name or ''] "
    + "if b == nil then b = (${cm} + (m and m.id or 0)) * ${n} end "
    + "local w = hl.get_active_workspace() "
    + "if w and w.special then w = m and m.active_workspace end "
    + "local o = ((w and w.id) or (b + 1)) - b "
    + "if o < 1 or o > ${n} then o = 1 end "
    + "return b + ((o - 1 + (${d})) % ${n}) + 1 "
    + "end)(), on_current_monitor = true})\"";

  # Lua literal for monitor option values ("auto" -> "auto", 1.25 -> 1.25).
  # toJSON already emits valid Lua for strings, integers and floats.
  luaScalar = v: builtins.toJSON v;

  # The internal panel of a laptop is the first configured output (eDP-1).
  # Used to switch only the laptop panel off when the lid closes.
  lidPanel = if cfg.monitors == [ ] then null else (lib.head cfg.monitors).output;

  # `hl.dsp.dpms` takes a `monitor` selector (not `output`); without one it
  # applies to every output.
  lidDpmsOff =
    if lidPanel == null then
      ''{ action = "disable" }''
    else
      ''{ action = "disable", monitor = ${luaScalar lidPanel} }'';

  # Pause every MPRIS player (browsers, mpv, spotify, ...). `|| true` keeps the
  # lid-close command and hypridle's `before_sleep_cmd` from failing when
  # nothing is playing (playerctl exits non-zero on "no players found").
  pauseMediaCmd = "${pkgs.playerctl}/bin/playerctl -a pause || true";

  # Configured monitors plus the catch-all fallback for hot-plugged outputs.
  monitors = cfg.monitors ++ [
    {
      output = "";
      mode = "preferred";
      position = "auto";
      scale = "auto";
    }
  ];

  monitorLua = lib.concatMapStringsSep "\n" (m: ''
    hl.monitor({
      output = ${luaScalar m.output},
      mode = ${luaScalar m.mode},
      position = ${luaScalar m.position},
      scale = ${luaScalar m.scale},
    })
  '') monitors;

  # Every configured monitor owns its own block of `workspaceCount` workspaces:
  # the first one 1..9, the second 10..18, and so on. `base` is the 0-based
  # offset of that block.
  monitorBases = lib.imap0 (idx: m: {
    output = m.output;
    base = idx * workspaceCount;
  }) cfg.monitors;

  # `hl.workspace_rule` (Hyprland 0.57.2 Lua: `workspace` is a required string
  # selector, `monitor` a monitor selector, `default` a bool that makes the
  # workspace the monitor's initial one - CWorkspaceRuleManager::
  # getDefaultWorkspaceFor). Without the `default` rules Hyprland gives a fresh
  # monitor the lowest id not bound elsewhere, which is how the second monitor
  # ended up on a stray workspace 2.
  workspaceRulesLua = lib.concatMapStringsSep "\n" (
    m:
    lib.concatMapStringsSep "\n" (
      i:
      "hl.workspace_rule({ workspace = \"${toString i}\", monitor = ${luaScalar m.output}${
        lib.optionalString (i == m.base + 1) ", default = true"
      } })"
    ) (lib.range (m.base + 1) (m.base + workspaceCount))
  ) monitorBases;

  # Lua table of `output -> 0-based base offset` for the configured monitors
  # (`{ ["DP-3"] = 0, ["DP-1"] = 9 }`), used by the workspace keybinds,
  # `cycle_workspace` and the Waybar scroll command. `quote` is `"` in
  # hyprland.lua and `'` inside the one-line `hyprctl dispatch` commands, which
  # sit in shell double quotes.
  monitorBaseTable =
    quote:
    "{ "
    + lib.concatMapStringsSep ", " (
      m: "[${quote}${m.output}${quote}] = ${toString m.base}"
    ) monitorBases
    + " }";

  # Waybar 0.16 `hyprland/workspaces`: keys are output names and a non-empty
  # array value is the list of workspace *selectors* to always show on that
  # output (src/modules/hyprland/workspaces.cpp:
  # loadPersistentWorkspacesFromConfig -> `workspace.asString()`), so the names
  # match `hl.workspace_rule` exactly and do not depend on Hyprland's runtime
  # monitor id. Never emit an empty array: Waybar reads that as "a workspace
  # named after the key, on every monitor".
  #
  # There is deliberately no `"*"` fallback any more. An int value expands to
  # `id * workspaceCount + 1..` on that monitor (Hyprland's runtime monitor id),
  # which cannot express the block an *unconfigured* hot-plugged output gets
  # (see `focused_base`), so a `"*"` entry could hand out another monitor's
  # workspace ids and make its bar buttons switch the wrong monitor. Without it
  # an unconfigured output simply lists the workspaces it actually has (Waybar
  # filters per monitor: `all-outputs` is off), and every click dispatches a
  # workspace that lives on that monitor.
  persistentWorkspaces = lib.listToAttrs (
    lib.imap0 (idx: m: {
      name = m.output;
      value = map toString (lib.range (idx * workspaceCount + 1) ((idx + 1) * workspaceCount));
    }) cfg.monitors
  );

  # `format = "{icon}"` plus this map: each bar relabels its own block 1..9, so
  # every monitor shows the same tag row while controlling an independent
  # workspace set. Waybar matches `format-icons` on the workspace *name*
  # (Workspace::selectString), falling back to the raw name when unmapped.
  # Covers 6 monitors (54 workspaces), the configured ones plus hot-plugged
  # outputs that get a block after them.
  workspaceIcons = lib.listToAttrs (
    map (n: {
      name = toString n;
      value = toString (lib.mod (n - 1) workspaceCount + 1);
    }) (lib.range 1 (6 * workspaceCount))
  );

  hasBattery = cfg.isLaptop || cfg.batteryName != null;

  hypridleListeners =
    lib.optional (cfg.idleLockTimeout != null) {
      timeout = cfg.idleLockTimeout;
      on-timeout = "pidof hyprlock || hyprlock";
    }
    ++ lib.optional (cfg.idleDpmsTimeout != null) {
      timeout = cfg.idleDpmsTimeout;
      on-timeout = "hyprctl dispatch 'hl.dsp.dpms({ action = \"disable\" })'";
      on-resume = "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'";
    };

  hyprlandLua = ''
    -- Hyprland 0.57+ Lua configuration matching AwesomeWM look & feel.
    -- Generated from modules/hyprland-home.nix (custom.hyprland.* options).

    ------------------
    ---- MONITORS ----
    ------------------
    ${monitorLua}

    ${lib.optionalString (cfg.monitors != [ ]) ''
      -----------------------------
      ---- WORKSPACE BINDING ----
      -----------------------------
      -- One independent block of ${toString workspaceCount} workspaces per configured
      -- monitor (first monitor 1-${toString workspaceCount}, second ${toString (workspaceCount + 1)}-${toString (2 * workspaceCount)}, ...).
      -- A monitor can only ever display workspaces of its own block, which is
      -- what unlinks the two monitors: switching a tag on one of them cannot
      -- reach the other one's workspaces.
      -- `default = true` pins the monitor's initial workspace to the first id of
      -- its own block instead of letting Hyprland pick the lowest free id.
      ${workspaceRulesLua}
    ''}

    -------------------------------
    ---- ENVIRONMENT VARIABLES ----
    -------------------------------
    hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")
    hl.env("XCURSOR_SIZE", "20")
    hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Classic")
    hl.env("HYPRCURSOR_SIZE", "20")

    -----------------------
    ---- LOOK AND FEEL ----
    -----------------------
    hl.config({
      general = {
        gaps_in = 5,
        gaps_out = 10,
        border_size = 3,
        col = {
          active_border = "rgb(875fff)",
          inactive_border = "rgb(111111)",
        },
        -- Drag the border (or the extended grab area around it) to resize.
        resize_on_border = true,
        extend_border_grab_area = 15,
        allow_tearing = false,
        -- Default layout: master (AwesomeWM `tile`). SUPER+Space / the Waybar
        -- layout box flip to dwindle, and the `dwindle` block below still
        -- applies while dwindle is active.
        layout = "master",
      },

      decoration = {
        -- Subtle rounding: enough to read as "modern", never bubbly.
        rounding = 6,
        rounding_power = 2,
        active_opacity = 1.0,
        inactive_opacity = 1.0,
        shadow = {
          enabled = true,
          range = 7,
          render_power = 3,
          color = "rgba(000000bb)",
        },
        blur = {
          -- Blur stays off: pure #000000 wallpaper + OLED battery life.
          enabled = false,
        },
      },

      animations = {
        enabled = true,
      },

      dwindle = {
        force_split = 2,
        preserve_split = true,
      },

      master = {
        mfact = 0.50,
        new_status = "slave",
      },

      -- msm_dpu (yogabook) has no HDR_OUTPUT_METADATA support, so with the
      -- colour-management pipeline on every commit logs `failed to commit hdr
      -- metadata: no HDR_OUTPUT_METADATA prop support` and HDR mode switches
      -- flash/tear. Hyprland 0.57.2: `render:cm_enabled` (default true, needs a
      -- restart for full effect) — keep the plain sRGB path.
      render = {
        cm_enabled = false,
      },

      misc = {
        background_color = "0x000000",
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        force_default_wallpaper = 0,
        key_press_enables_dpms = true,
        mouse_move_enables_dpms = true,
        -- `misc:vfr` no longer exists in Hyprland 0.57.2 (there is no such
        -- option: `hyprctl getoption misc:vfr` -> "no such option", and the
        -- string is absent from the binary), so the old "enable variable frame
        -- rate to save power" knob is simply gone — do not re-add it.
        -- 0 = off, 1 = on, 2 = fullscreen only
        vrr = ${toString cfg.vrr},
      },

      xwayland = {
        force_zero_scaling = true,
      },

      ${primaryMonitorCursorLua}

      input = {
        kb_layout = "us",
        follow_mouse = 1,
        sensitivity = 0,
        touchpad = {
          natural_scroll = true,
          tap_to_click = true,
          disable_while_typing = true,
          -- Hyprland's default (1.0) scrolls far too fast on the ELAN06FA
          -- precision touchpad. 0.4 keeps ~2.5x more scroll distance per swipe
          -- without touching `natural_scroll` or the scroll method.
          scroll_factor = 0.4,
        },
      },
    })

    ----------------------
    ---- ANIMATIONS ----
    ----------------------
    -- `speed` is in deciseconds (1 = 100 ms), so 1.5-1.8 is a 150-180 ms
    -- transition: crisp and snappy, no sluggish easing. The curves are defined
    -- here because the packaged default config (which declares them) is only
    -- used when no config exists - our file replaces it.
    hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
    hl.curve("almostLinear", { type = "bezier", points = { { 0.5, 0.5 }, { 0.75, 1 } } })

    hl.animation({ leaf = "windows", enabled = true, speed = 1.8, bezier = "easeOutQuint" })
    hl.animation({ leaf = "windowsIn", enabled = true, speed = 1.5, bezier = "easeOutQuint", style = "popin 95%" })
    hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.5, bezier = "easeOutQuint", style = "popin 95%" })
    hl.animation({ leaf = "fade", enabled = true, speed = 1.5, bezier = "easeOutQuint" })
    hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.5, bezier = "easeOutQuint" })
    hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.5, bezier = "easeOutQuint" })
    hl.animation({ leaf = "workspaces", enabled = true, speed = 1.8, bezier = "easeOutQuint", style = "fade" })
    -- Layers: Waybar's tray drawer, the Swaync control center and the SwayOSD
    -- popup are layer surfaces.
    hl.animation({ leaf = "layers", enabled = true, speed = 1.5, bezier = "easeOutQuint" })
    hl.animation({ leaf = "layersIn", enabled = true, speed = 1.5, bezier = "easeOutQuint", style = "fade" })
    hl.animation({ leaf = "layersOut", enabled = true, speed = 1.5, bezier = "easeOutQuint", style = "fade" })
    hl.animation({ leaf = "border", enabled = true, speed = 1.5, bezier = "easeOutQuint" })

    ${lib.optionalString cfg.isLaptop ''
      -- 3-finger horizontal swipe to switch workspaces on the touchpad.
      -- workspace_swipe_create_new would otherwise create workspace 10, 11, ...
      -- when swiping right from the last workspace (Hyprland default: true).
      -- This is Hyprland's native `workspace` gesture (not cycle_workspace), so
      -- it steps through workspace ids: with a second monitor attached, a swipe
      -- past the last workspace of this monitor lands on that monitor's block.
      hl.config({ gestures = { workspace_swipe_create_new = false } })

      hl.gesture({
        fingers = 3,
        direction = "horizontal",
        action = "workspace",
      })
    ''}
    -------------------
    ---- AUTOSTART ----
    -------------------
    hl.on("hyprland.start", function()
      hl.exec_cmd("copyq")
      hl.exec_cmd("udiskie --tray")
      ${primaryMonitorXrandrLua}
    end)

    ---------------------------
    ---- WORKSPACE CYCLING ----
    ---------------------------
    -- Every monitor owns its own block of WORKSPACE_COUNT workspaces (see the
    -- `hl.workspace_rule` bindings above). Hyprland's relative selectors
    -- (r+1 / r-1) walk across monitors and would spawn workspace ids outside
    -- the block, so every bind resolves an absolute id inside the focused
    -- monitor's block instead.
    local WORKSPACE_COUNT = ${toString workspaceCount}

    -- Number of monitors configured in custom.hyprland.monitors (they own the
    -- blocks 1-9, 10-18, ...).
    local CONFIGURED_MONITORS = ${toString configuredMonitorCount}

    -- Output name -> 0-based base offset of its block, generated from
    -- custom.hyprland.monitors (`{ ["DP-3"] = 0, ["DP-1"] = 9 }`).
    local MONITOR_BASE = ${monitorBaseTable "\""}

    -- Base offset of the focused monitor. An output missing from MONITOR_BASE
    -- (hot-plugged) gets a block *after* the configured ones, so it can never
    -- collide with a configured monitor's block - a collision would make
    -- SUPER+1 on the hot-plugged output switch the configured monitor instead.
    local function focused_base()
      local mon = hl.get_active_monitor()
      if not mon then
        return 0
      end
      local base = MONITOR_BASE[mon.name or ""]
      if base ~= nil then
        return base
      end
      return (CONFIGURED_MONITORS + (mon.id or 0)) * WORKSPACE_COUNT
    end

    -- Workspace the focused monitor is on, ignoring a peeked special workspace
    -- (`special:minimized` has a negative id).
    local function focused_workspace_id()
      local ws = hl.get_active_workspace()
      if ws and ws.special then
        local mon = hl.get_active_monitor()
        ws = mon and mon.active_workspace or nil
      end
      return ws and ws.id or nil
    end

    -- Cycle inside the focused monitor's block, wrapping at its edges.
    -- `on_current_monitor` keeps the switch on the focused monitor (Hyprland's
    -- plain `workspace` dispatcher would switch the monitor that owns the id and
    -- move focus there).
    local function cycle_workspace(delta)
      local base = focused_base()
      local offset = (focused_workspace_id() or (base + 1)) - base
      if offset < 1 or offset > WORKSPACE_COUNT then
        offset = 1
      end
      hl.dispatch(hl.dsp.focus({ workspace = base + ((offset - 1 + delta) % WORKSPACE_COUNT) + 1, on_current_monitor = true }))
    end

    ------------------------------
    ---- FLOATING WINDOW LAYOUT ----
    ------------------------------
    -- Hyprland only *translates* an oversized floating window back on-screen
    -- (`misc:new_float_force_onscreen`), it never shrinks it, and its `center`
    -- dispatcher centres on the monitor's logical box *without* the Waybar
    -- reserve. A big window toggled to floating therefore kept its tiled size
    -- (e.g. 1510x910 on a 1536x936 work area) and its titlebar ended up behind
    -- the bar. Cap floating windows at 80% of the usable work area and centre
    -- them inside it, where "usable" is the monitor's logical size (pixels /
    -- `scale`) minus `monitor.reserved` (Waybar's top bar).
    -- Windows are never *enlarged*: small dialogs/calculators/PiP keep their own
    -- size, and they are only re-positioned when they actually reach into the
    -- reserved strip or off the work area.
    local FLOAT_MAX_FRACTION = 0.8

    local function work_area(mon)
      if not mon then
        return nil
      end
      local scale = mon.scale or 1.0
      if scale <= 0 then
        scale = 1.0
      end
      local res = mon.reserved or {}
      local left, top = res.left or 0, res.top or 0
      local right, bottom = res.right or 0, res.bottom or 0
      local w = mon.width / scale - left - right
      local h = mon.height / scale - top - bottom
      if w <= 0 or h <= 0 then
        return nil
      end
      return { x = mon.x + left, y = mon.y + top, w = w, h = h }
    end

    -- Fit/centre a floating window inside the work area. `center` forces the
    -- re-centre (used when a window *becomes* floating); otherwise the window is
    -- only moved when it would sit under the bar or outside the work area.
    local function fit_floating(win, center)
      if not win or not win.floating then
        return
      end
      -- `win.fullscreen` is an integer mode (0 = none, and 0 is truthy in Lua).
      local fs = win.fullscreen
      if fs and fs ~= 0 then
        return
      end

      local area = work_area(win.monitor or hl.get_active_monitor())
      if not area then
        return
      end

      local maxw = math.floor(area.w * FLOAT_MAX_FRACTION)
      local maxh = math.floor(area.h * FLOAT_MAX_FRACTION)

      local size, pos = win.size, win.at
      local w, h = math.floor(size.x), math.floor(size.y)
      local x, y = math.floor(pos.x), math.floor(pos.y)
      -- Never upscale: only clamp windows that are bigger than the cap.
      local neww, newh = math.min(w, maxw), math.min(h, maxh)

      local newx, newy = x, y
      local outside = x < area.x or y < area.y or (x + neww) > (area.x + area.w) or (y + newh) > (area.y + area.h)
      if center or outside then
        newx = math.floor(area.x + (area.w - neww) / 2)
        newy = math.floor(area.y + (area.h - newh) / 2)
      end

      if neww == w and newh == h and newx == x and newy == y then
        return
      end

      if neww ~= w or newh ~= h then
        hl.dispatch(hl.dsp.window.resize({ window = win, x = neww, y = newh, relative = false }))
      end
      if newx ~= x or newy ~= y then
        hl.dispatch(hl.dsp.window.move({ window = win, x = newx, y = newy, relative = false }))
      end
    end

    -- Newly opened floating windows (window rules with `float = true`, dialogs,
    -- PiP). Small windows already fit, so they are left untouched; empty-class
    -- XWayland windows are drag proxies/menus and are skipped entirely.
    hl.on("window.open", function(win)
      if not win or win.pinned then
        return
      end
      if win.xwayland and (win.class or "") == "" then
        return
      end
      fit_floating(win, false)
    end)

    -- Windows that become floating later: SUPER+CTRL+Space, satty's annotation
    -- window, `setprop floating`, plugin/mouse rules. Pinned windows place
    -- themselves and are left alone.
    hl.on("window.update_state", function(win, changes)
      if not win or not changes.float or win.pinned then
        return
      end
      fit_floating(win, true)
    end)

    ---------------------
    ---- KEYBINDINGS ----
    ---------------------
    local mainMod = "SUPER"
    local terminal = "kitty"

    -- Standard programs & session control (matching dotfiles/awesome/rc.lua)
    hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal), { description = "open terminal" })
    hl.bind(
      mainMod .. " + SHIFT + Return",
      hl.dsp.exec_cmd(terminal, { float = true, size = "900 630", center = true }),
      { description = "open floating terminal" }
    )
    hl.bind(mainMod .. " + SHIFT + C", hl.dsp.window.close(), { description = "close window" })
    hl.bind(mainMod .. " + CONTROL + R", hl.dsp.reload_config(), { description = "reload hyprland" })
    hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.exit(), { description = "quit hyprland" })

    -- Launchers & lock (rofi 2.x native Wayland + hyprlock)
    hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("rofi -show drun -disable-history -show-icons"), { description = "rofi drun" })
    hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("rofi -show run -disable-history -show-icons"), { description = "rofi run" })
    hl.bind(mainMod .. " + E", hl.dsp.exec_cmd("rofi -show emoji -modi emoji -emoji-mode copy"), { description = "rofi emoji" })
    hl.bind(mainMod .. " + CONTROL + L", hl.dsp.exec_cmd("pidof hyprlock || hyprlock"), { description = "lock screen" })
    -- Swaync control center (notification daemon runs as a systemd user unit,
    -- see services.swaync). SUPER+N is taken by minimize.
    hl.bind(
      mainMod .. " + A",
      hl.dsp.exec_cmd("${pkgs.swaynotificationcenter}/bin/swaync-client -t -sw"),
      { description = "toggle notification center" }
    )

    -- Workspace navigation, bounded to each monitor's own block of
    -- WORKSPACE_COUNT workspaces (wrapping like AwesomeWM's tags). SUPER+1..9
    -- and SUPER+SHIFT+1..9 act on the focused monitor, so both monitors show
    -- the same 1-9 keys and Waybar labels while owning separate workspaces.
    -- `on_current_monitor = true` (Hyprland's `focusworkspaceoncurrentmonitor`)
    -- is what keeps them separate: the plain `workspace` dispatcher switches
    -- the id on the monitor that owns it and moves focus there, so asking for
    -- workspace 1 on the second monitor switched the first one instead.
    -- SUPER+Escape is the exception: it is a focus-history jump, so it may land
    -- on the other monitor (it still only switches that one).
    hl.bind(mainMod .. " + Left", function() cycle_workspace(-1) end, { description = "previous workspace" })
    hl.bind(mainMod .. " + Right", function() cycle_workspace(1) end, { description = "next workspace" })
    hl.bind(mainMod .. " + Escape", hl.dsp.focus({ workspace = "previous" }), { description = "restore previous workspace" })

    for i = 1, WORKSPACE_COUNT do
      hl.bind(mainMod .. " + " .. i, function()
        hl.dispatch(hl.dsp.focus({ workspace = focused_base() + i, on_current_monitor = true }))
      end, { description = "workspace " .. i })
      hl.bind(mainMod .. " + SHIFT + " .. i, function()
        hl.dispatch(hl.dsp.window.move({ workspace = focused_base() + i, follow = false }))
      end, { description = "move window to workspace " .. i })
    end

    -- Client focus & swapping
    hl.bind(mainMod .. " + J", hl.dsp.window.cycle_next(), { description = "focus next window" })
    hl.bind(mainMod .. " + K", hl.dsp.window.cycle_next({ next = false }), { description = "focus previous window" })
    hl.bind(mainMod .. " + SHIFT + J", hl.dsp.window.swap({ next = true }), { description = "swap with next window" })
    hl.bind(mainMod .. " + SHIFT + K", hl.dsp.window.swap({ prev = true }), { description = "swap with previous window" })
    hl.bind(mainMod .. " + CONTROL + J", hl.dsp.focus({ monitor = "+1" }), { description = "focus next monitor" })
    hl.bind(mainMod .. " + CONTROL + K", hl.dsp.focus({ monitor = "-1" }), { description = "focus previous monitor" })
    hl.bind(mainMod .. " + U", hl.dsp.focus({ urgent_or_last = true }), { description = "jump to urgent window" })
    hl.bind(mainMod .. " + Tab", hl.dsp.focus({ last = true }), { description = "focus previous window" })

    -- Window resizing. `hl.dsp.window.resize` maps to Hyprland's `resizeactive`
    -- dispatcher: relative x/y deltas, and it works for tiled *and* floating
    -- windows (tiled windows just change the layout split instead of a box).
    local resizeStep = 40

    local function resize_active(dx, dy)
      if not hl.get_active_window() then
        return
      end
      hl.dispatch(hl.dsp.window.resize({ x = dx, y = dy, relative = true }))
    end

    -- Layout manipulation (master <-> dwindle, split ratio / mfact).
    -- `mfact` / `splitratio` are layout-only and take *relative* deltas, so
    -- floating windows fall back to a plain resize instead of doing nothing.
    -- The layout actually in effect is the workspace's `tiled_layout`; the
    -- global `general.layout` option is only the fallback for a workspace that
    -- has not picked one yet. (Both `hl.get_config("general.layout")` and
    -- `hl.get_config("general:layout")` resolve, but neither is per-workspace.)
    local function current_layout()
      local ws = hl.get_active_workspace()
      if ws then
        local layout = ws.tiled_layout
        if layout and layout ~= "" then
          return layout
        end
      end
      return hl.get_config("general.layout") or "master"
    end

    local function adjust_split(delta)
      local win = hl.get_active_window()
      if win and win.floating then
        resize_active(math.floor(delta * 800), 0)
        return
      end
      local layout = current_layout()
      if layout == "master" then
        hl.dispatch(hl.dsp.layout(string.format("mfact %+.2f", delta)))
      else
        hl.dispatch(hl.dsp.layout(string.format("splitratio %+.2f", delta)))
      end
    end

    hl.bind(mainMod .. " + H", function() adjust_split(-0.05) end, { repeating = true, description = "shrink window / decrease split factor" })
    hl.bind(mainMod .. " + L", function() adjust_split(0.05) end, { repeating = true, description = "grow window / increase split factor" })
    hl.bind(mainMod .. " + equal", function() adjust_split(0.05) end, { repeating = true, description = "grow window / increase split factor" })
    hl.bind(mainMod .. " + minus", function() adjust_split(-0.05) end, { repeating = true, description = "shrink window / decrease split factor" })

    -- Fine-grained keyboard resizing (tiled and floating, repeats while held)
    hl.bind(mainMod .. " + ALT + H", function() resize_active(-resizeStep, 0) end, { repeating = true, description = "resize: shrink width" })
    hl.bind(mainMod .. " + ALT + Left", function() resize_active(-resizeStep, 0) end, { repeating = true, description = "resize: shrink width" })
    hl.bind(mainMod .. " + ALT + L", function() resize_active(resizeStep, 0) end, { repeating = true, description = "resize: grow width" })
    hl.bind(mainMod .. " + ALT + Right", function() resize_active(resizeStep, 0) end, { repeating = true, description = "resize: grow width" })
    hl.bind(mainMod .. " + ALT + K", function() resize_active(0, -resizeStep) end, { repeating = true, description = "resize: shrink height" })
    hl.bind(mainMod .. " + ALT + Up", function() resize_active(0, -resizeStep) end, { repeating = true, description = "resize: shrink height" })
    hl.bind(mainMod .. " + ALT + J", function() resize_active(0, resizeStep) end, { repeating = true, description = "resize: grow height" })
    hl.bind(mainMod .. " + ALT + Down", function() resize_active(0, resizeStep) end, { repeating = true, description = "resize: grow height" })

    -- AwesomeWM's `Mod4 + space`: flip master <-> dwindle and poke Waybar's
    -- `custom/layout` indicator (`signal = 8` = SIGRTMIN+8) so it re-reads the
    -- layout immediately instead of showing a stale label.
    hl.bind(mainMod .. " + space", function()
      local next_layout = (current_layout() == "dwindle") and "master" or "dwindle"
      hl.config({ general = { layout = next_layout } })
      hl.dispatch(hl.dsp.exec_cmd("${pkgs.procps}/bin/pkill -RTMIN+8 waybar"))
    end, { description = "toggle dwindle / master layout" })

    -- Client states (matching AwesomeWM: G=fullscreen, M=maximize, Ctrl+Space=float, Ctrl+Return=master, O=screen, T=pin)
    hl.bind(mainMod .. " + G", hl.dsp.window.fullscreen({ mode = "fullscreen" }), { description = "toggle fullscreen" })
    hl.bind(mainMod .. " + M", hl.dsp.window.fullscreen({ mode = "maximized" }), { description = "toggle maximize" })
    hl.bind(mainMod .. " + CONTROL + space", function()
      hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
      fit_floating(hl.get_active_window(), true)
    end, { description = "toggle floating (centered)" })
    -- `swapwithmaster` is a master-only layoutmsg: on dwindle Hyprland answers
    -- "Unknown dwindle layoutmsg" and nothing happens. dwindle's equivalent is
    -- `movetoroot`, which promotes the focused window to the root (master) slot.
    -- Both verified live against Hyprland 0.57.2 (each errors out in the other
    -- layout), so pick by the workspace's actual layout.
    local function swap_with_master()
      if current_layout() == "master" then
        hl.dispatch(hl.dsp.layout("swapwithmaster"))
      else
        hl.dispatch(hl.dsp.layout("movetoroot"))
      end
    end

    hl.bind(mainMod .. " + CONTROL + Return", swap_with_master, { description = "swap with master" })
    hl.bind(mainMod .. " + O", hl.dsp.window.move({ monitor = "+1" }), { description = "move window to next monitor" })
    hl.bind(mainMod .. " + T", hl.dsp.window.pin(), { description = "toggle pin / keep on top (floating)" })

    -- Minimize / restore (matching dotfiles/awesome/rc.lua modkey+n / modkey+Control+n).
    -- Minimized clients are parked on the hidden "special:minimized" workspace
    -- and tagged `minimized-ws-<N>` with the workspace they were minimized from.
    -- The tag is what makes them per-workspace: Waybar's `cffi/taskbar` reads
    -- `hyprctl -j clients` and lists a workspace's minimized windows next to its
    -- visible ones (left click restores + focuses, middle click minimizes),
    -- while SUPER+SHIFT+N still peeks at all of them at once. Verified against
    -- Hyprland 0.57.2: `hl.dsp.window.tag({ tag = ..., window = ... })`,
    -- `clear_tags` and `move({ workspace = <id>, follow = true, window = ... })`
    -- (follow = true also focuses the window, which a window on the hidden
    -- special workspace cannot be made to do directly: `hl.dsp.focus` on it
    -- would open the special workspace instead).
    local MINIMIZED_WORKSPACE = "special:minimized"
    local MINIMIZED_TAG_PREFIX = "minimized-ws-"

    -- Restore order only (newest last); the workspace attribution lives in the
    -- tag, so it survives a config reload.
    local minimized = {}

    local function minimized_tag(ws_id)
      return MINIMIZED_TAG_PREFIX .. tostring(ws_id)
    end

    -- Workspace a minimized window was minimized from, nil when untagged (a
    -- window parked there before this tagging existed).
    local function minimized_workspace_id(win)
      if not (win and win.tags) then
        return nil
      end
      for _, tag in ipairs(win.tags) do
        if type(tag) == "string" and tag:sub(1, #MINIMIZED_TAG_PREFIX) == MINIMIZED_TAG_PREFIX then
          local id = tonumber(tag:sub(#MINIMIZED_TAG_PREFIX + 1))
          if id then
            return id
          end
        end
      end
      return nil
    end

    local function is_minimized(win)
      return win ~= nil and win.workspace ~= nil and win.workspace.name == MINIMIZED_WORKSPACE
    end

    -- The workspace a keybind should act on. While the minimize workspace is
    -- being peeked at, the special one is never a valid target.
    local function target_workspace_id()
      local ws = hl.get_active_workspace()
      if ws and ws.special then
        ws = hl.get_last_workspace()
      end
      return ws and ws.id or nil
    end

    local function minimize_window(win, ws_id)
      if not win or not ws_id or is_minimized(win) then
        return
      end
      -- `tagwindow` adds to the tag set, so clear first: a window that was
      -- restored and minimized again must not keep the previous workspace tag.
      hl.dispatch(hl.dsp.window.clear_tags({ window = win }))
      hl.dispatch(hl.dsp.window.tag({ tag = minimized_tag(ws_id), window = win }))
      hl.dispatch(hl.dsp.window.move({ workspace = MINIMIZED_WORKSPACE, follow = false, window = win }))
      minimized[#minimized + 1] = { address = win.address, workspace = ws_id }
    end

    local function minimize_active()
      minimize_window(hl.get_active_window(), target_workspace_id())
    end

    -- Newest minimized window of `ws_id`: the restore stack first (LIFO), then
    -- the tags for the stale-stack case (e.g. after a config reload), and
    -- finally an untagged legacy window, which has no workspace to go back to.
    local function pop_minimized(ws_id)
      if not ws_id then
        return nil
      end
      for i = #minimized, 1, -1 do
        local entry = minimized[i]
        if entry.workspace == ws_id then
          table.remove(minimized, i)
          local candidate = hl.get_window("address:" .. entry.address)
          if is_minimized(candidate) then
            return candidate
          end
        end
      end

      local hidden = hl.get_windows({ workspace = MINIMIZED_WORKSPACE })
      local legacy
      for i = #hidden, 1, -1 do
        local owner = minimized_workspace_id(hidden[i])
        if owner == ws_id then
          return hidden[i]
        end
        if not owner then
          legacy = hidden[i]
        end
      end
      return legacy
    end

    local function restore_window(win, ws_id)
      if not win or not ws_id then
        return
      end
      hl.dispatch(hl.dsp.window.clear_tags({ window = win }))
      -- One dispatch restores *and* focuses (follow = true -> silent = false),
      -- and it closes the peeked special workspace when restoring from a peek.
      hl.dispatch(hl.dsp.window.move({ workspace = ws_id, follow = true, window = win }))
    end

    local function restore_minimized()
      local ws_id = target_workspace_id()
      restore_window(pop_minimized(ws_id), ws_id)
    end

    hl.bind(mainMod .. " + N", minimize_active, { description = "minimize window" })
    hl.bind(mainMod .. " + CONTROL + N", restore_minimized, { description = "restore minimized window" })
    hl.bind(
      mainMod .. " + SHIFT + N",
      hl.dsp.workspace.toggle_special("minimized"),
      { description = "peek at minimized windows" }
    )

    -- Mouse bindings
    hl.bind(mainMod .. " + mouse_down", function() cycle_workspace(1) end, { description = "next workspace" })
    hl.bind(mainMod .. " + mouse_up", function() cycle_workspace(-1) end, { description = "previous workspace" })
    hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
    hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

    -- Media and volume keys
    hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
    hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
    hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
    hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })
    hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("${volumeScript} up"), { locked = true, repeating = true })
    hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("${volumeScript} down"), { locked = true, repeating = true })
    hl.bind("XF86AudioMute", hl.dsp.exec_cmd("${volumeScript} mute"), { locked = true })
    hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("${micMuteScript}/bin/hypr-mic-mute"), { locked = true })
    -- Caps Lock OSD. `swayosd-client --caps-lock` reads the kernel LED
    -- (/sys/class/leds/*capslock), so no root libinput daemon is needed;
    -- `non_consuming` keeps the lock itself reaching the focused window.
    hl.bind(
      "Caps_Lock",
      hl.dsp.exec_cmd("${pkgs.swayosd}/bin/swayosd-client --caps-lock"),
      { locked = true, non_consuming = true, description = "caps lock OSD" }
    )
    ${lib.optionalString cfg.isLaptop ''
      -- Panel backlight (laptops only; desktops have no brightness device)
      hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("${brightnessScript} up"), { locked = true, repeating = true })
      hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("${brightnessScript} down"), { locked = true, repeating = true })

      -- Lid switch (laptops only). logind handles the lock itself
      -- (`HandleLidSwitch = lock` -> hypridle runs lock_cmd), this also pauses
      -- all media playback and powers the panel down so nothing lights up in a
      -- bag. `locked = true` makes the bind a `bindl`, so it still fires while
      -- hyprlock is up.
      -- The device name comes from libinput (Aquamarine uses it verbatim):
      -- most laptops expose "Lid Switch", the Yoga Slim 7 reports "gpio-keys".
      hl.bind("switch:on:${cfg.lidSwitchName}", function()
        hl.dispatch(hl.dsp.exec_cmd("${pauseMediaCmd}; pidof hyprlock || hyprlock"))
        hl.dispatch(hl.dsp.dpms(${lidDpmsOff}))
      end, { locked = true, description = "lid close: pause media, lock, panel off" })

      -- Lid open: panel back on. Playback is deliberately not resumed.
      hl.bind("switch:off:${cfg.lidSwitchName}", function()
        hl.dispatch(hl.dsp.dpms({ action = "enable" }))
      end, { locked = true, description = "lid open: panel on" })
    ''}
    -- Screenshots (grim + satty): Print grabs the focused monitor instantly
    -- (PNG + clipboard + notification), CTRL+Print selects a region and opens
    -- it in satty, SHIFT+Print sends the monitor straight to satty.
    hl.bind("Print", hl.dsp.exec_cmd("${screenshotScript}/bin/hypr-screenshot monitor"), { description = "screenshot monitor" })
    hl.bind("CONTROL + Print", hl.dsp.exec_cmd("${screenshotScript}/bin/hypr-screenshot region"), { description = "screenshot selection" })
    hl.bind("SHIFT + Print", hl.dsp.exec_cmd("${screenshotScript}/bin/hypr-screenshot monitor-edit"), { description = "screenshot monitor in satty" })

    ----------------------
    ---- WINDOW RULES ----
    ----------------------
    hl.window_rule({
      name = "suppress-maximize-events",
      match = { class = ".*" },
      suppress_event = "maximize",
    })

    hl.window_rule({
      name = "fix-xwayland-drags",
      match = {
        class = "^$",
        title = "^$",
        xwayland = true,
        float = true,
        fullscreen = false,
        pin = false,
      },
      no_focus = true,
    })

    -- satty (screenshot annotation): its window is a plain xdg_toplevel, so
    -- Hyprland has to float it itself; no titlebar (see the hyprbars rules
    -- below) because satty's own toolbar is the whole point.
    hl.window_rule({
      name = "satty",
      match = { class = "^(com\\.gabm\\.satty)$" },
      float = true,
      center = true,
    })

    -- Floating utility windows (matching dotfiles/awesome/rc.lua rules)
    for _, cls in ipairs({
      "^(com\\.github\\.hluk\\.copyq|copyq)$",
      "^(nemo|Nemo)$",
      "^(org\\.kde\\.ark|Ark)$",
      "^(org\\.kde\\.kleopatra|Kleopatra)$",
      "^(blueman-manager|Blueman-manager)$",
      "^(org\\.pulseaudio\\.pavucontrol|pavucontrol)$",
      "^(pinentry.*)$",
      "^(arandr|Arandr)$",
      "^(Tor Browser)$",
      "^(sxiv|Sxiv)$",
    }) do
      hl.window_rule({
        match = { class = cls },
        float = true,
        center = true,
      })
    end

    -- Waybar's TUI launchers (`kitty --class waybar-tui`, see the network,
    -- bluetooth and volume modules): one centred floating terminal, large
    -- enough for nmtui / bluetui and small enough for the 1536x960
    -- logical panel (1920x1200 @ 1.25) as well as any 1080p external.
    hl.window_rule({
      name = "waybar-tui",
      match = { class = "^(waybar-tui)$" },
      float = true,
      center = true,
      size = { 860, 560 },
    })

    -----------------------------
    ---- TITLEBARS (hyprbars) ----
    -----------------------------
    -- Home Manager renders `hl.plugin.load(".../libhyprbars.so")` at the top of this
    -- file; Hyprland loads the plugin at the end of the first config pass and then
    -- reloads, so the plugin's config keys only exist from the second pass on.
    -- Probing a plugin key keeps `Hyprland --verify-config` (which never loads
    -- plugins) free of "unknown config key" errors.
    if hl.get_config("plugin:hyprbars:bar_height") ~= nil then
      -- AwesomeWM titlebar palette (dotfiles/awesome/mytheme.lua):
      -- titlebar_bg_normal #111111 / titlebar_fg_normal #aaaaaa,
      -- titlebar_bg_focus #875fff / titlebar_fg_focus #ffffff.
      hl.config({
        plugin = {
          hyprbars = {
            enabled = true,
            bar_height = 22,
            bar_color = "rgb(111111)",
            col = { text = "rgb(ffffff)" },
            bar_text_font = "JetBrainsMono Nerd Font",
            bar_text_size = 11,
            bar_text_weight = "bold",
            bar_text_align = "center",
            bar_padding = 8,
            bar_part_of_window = true,
            bar_blur = false,
            on_double_click = "hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = \"maximized\" })'",
          },
        },
      })

      -- AwesomeWM draws titlebars on floating clients only: hyprbars decorates
      -- every window, so tiled clients, satty's annotation window and the
      -- invisible XWayland drag proxies get `no_bar`.
      hl.window_rule({
        name = "hyprbars-tiled",
        match = { float = false },
        ["hyprbars:no_bar"] = true,
      })
      hl.window_rule({
        name = "hyprbars-satty",
        match = { class = "^(com\\.gabm\\.satty)$" },
        ["hyprbars:no_bar"] = true,
      })
      hl.window_rule({
        name = "hyprbars-xwayland-drag-proxy",
        match = { class = "^$", title = "^$", xwayland = true },
        ["hyprbars:no_bar"] = true,
      })

      -- Focused floating window gets the purple AwesomeWM titlebar.
      hl.window_rule({
        name = "hyprbars-bar-focused",
        match = { focus = true },
        ["hyprbars:bar_color"] = "rgb(875fff)",
      })
      hl.window_rule({
        name = "hyprbars-bar-unfocused",
        match = { focus = false },
        ["hyprbars:title_color"] = "rgb(aaaaaa)",
      })
    end
  '';
in
{
  options.custom.hyprland = {
    monitors = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            output = lib.mkOption {
              type = lib.types.str;
              description = "Output name (eDP-1, DP-3, ...).";
            };
            mode = lib.mkOption {
              type = lib.types.str;
              default = "preferred";
              description = "Mode, e.g. 1920x1080@165.";
            };
            position = lib.mkOption {
              type = lib.types.str;
              default = "auto";
              description = "Position in the layout, e.g. 0x0.";
            };
            scale = lib.mkOption {
              type = lib.types.oneOf [
                lib.types.str
                lib.types.int
                lib.types.float
              ];
              default = "auto";
              description = "Scale factor, e.g. 1.25 or \"auto\".";
            };
          };
        }
      );
      default = [ ];
      description = ''
        Hyprland monitor layout. A catch-all `{ output = ""; mode = "preferred";
        position = "auto"; scale = "auto"; }` rule is always appended so
        hot-plugged outputs get a sane default.
      '';
    };

    isLaptop = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enables laptop-only features: panel backlight keys/script, the lid switch
        bind, the 3-finger workspace swipe and (unless overridden) the battery
        Waybar module.
      '';
    };

    lidSwitchName = lib.mkOption {
      type = lib.types.str;
      default = "Lid Switch";
      description = ''
        libinput device name of the lid switch, used for `switch:on:`/
        `switch:off:` binds. Aquamarine uses the kernel input name verbatim:
        most laptops report "Lid Switch", the Yoga Slim 7 14Q8Y11 reports
        "gpio-keys" (`hyprctl devices` -> Switches).
      '';
    };

    batteryName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Preferred battery device name for the Waybar `custom/battery` module.
        Discovery is dynamic (`type == Battery`), so this is only a tie-breaker
        when several batteries exist; it is not required for the module to work.
        When null and `isLaptop` is false, no battery module is shown at all.
      '';
    };

    primaryMonitor = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = if cfg.monitors != [ ] then (builtins.head cfg.monitors).output else null;
      defaultText = lib.literalExpression ''
        if cfg.monitors != [ ] then (builtins.head cfg.monitors).output else null
      '';
      description = ''
        Output that owns the cursor at startup (`cursor.default_monitor`) and is
        marked primary for XWayland via `xrandr --primary` on
        `hyprland.start`. Defaults to the first configured monitor; null keeps
        Hyprland's own choice.
      '';
    };

    vrr = lib.mkOption {
      type = lib.types.int;
      default = 0;
      description = ''
        `misc.vrr`: 0 = off, 1 = always on, 2 = fullscreen only. Use 0 on
        fixed-refresh (OLED) panels, 2 on mixed-refresh desktop setups.
      '';
    };

    idleLockTimeout = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = 300;
      description = ''
        Hypridle seconds of inactivity before locking, or null to disable the
        idle lock (lock-on-suspend stays enabled either way).
      '';
    };

    idleDpmsTimeout = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = 600;
      description = ''
        Hypridle seconds of inactivity before turning the displays off, or null
        to disable.
      '';
    };
  };

  config = {
    home.packages =
      with pkgs;
      [
        wl-clipboard
        cliphist
        # Screenshots: grim captures, slurp selects the region, satty annotates
        # (see screenshotScript above).
        grim
        slurp
        satty
        libnotify
        # Waybar TUI launcher: click on bluetooth opens this in a
        # floating `kitty --class waybar-tui` (window rule above).
        bluetui
      ]
      ++ lib.optional cfg.isLaptop brightnessctl;

    # Cursor theme for GTK, XWayland, and native Hyprland (hyprcursor)
    home.pointerCursor = {
      enable = true;
      gtk.enable = true;
      hyprcursor.enable = true;
    };

    # satty 0.22.0 screenshot annotation. Every key lives under `[general]`
    # (satty's config.toml is a four-section file: general, keybinds,
    # color-palette, font, and it rejects unknown keys — verified with
    # `satty -c <file> -f /dev/null`: a top-level key fails with "unknown
    # field ..., expected one of `general`, `color-palette`, `font`,
    # `keybinds`"). Enter copies (wl-copy) *and* saves, Escape just closes.
    xdg.configFile."satty/config.toml".text = ''
      [general]
      output-filename = "${config.home.homeDirectory}/Pictures/Screenshots/%Y-%m-%d_%H:%M:%S.png"
      copy-command = "wl-copy"
      save-after-copy = true
      early-exit = ["all"]
      actions-on-enter = ["save-to-clipboard"]
      actions-on-escape = ["exit"]
    '';

    # Hyprland 0.57+ Lua configuration; NixOS provides the package and xdg portal.
    wayland.windowManager.hyprland = {
      enable = true;
      package = null;
      portalPackage = null;
      configType = "lua";
      systemd.enable = true;
      # Home Manager renders these as `hl.plugin.load(".../lib<name>.so")` at the
      # top of hyprland.lua. nixpkgs builds hyprbars against the same pkgs.hyprland
      # (0.57.2), so the plugin's API/header hash matches the running compositor.
      plugins = [ pkgs.hyprlandPlugins.hyprbars ];
      extraConfig = hyprlandLua;
    };

    # Polkit authentication agent bound to graphical-session.target
    services.hyprpolkitagent.enable = true;

    # Waybar top status bar matching AwesomeWM's wibar (rc.lua + mytheme.lua)
    programs.waybar = {
      enable = true;
      systemd.enable = true;
      settings = {
        mainBar = {
          layer = "top";
          position = "top";
          height = 32;
          spacing = 6;
          # The taskbar lives in `modules-left` and `expand = true`, so Waybar
          # stretches it across every pixel between the tags/layout box and the
          # tray instead of letting `modules-center` shrink-wrap it.
          expand-left = true;
          no-center = true;
          modules-left = [
            "hyprland/workspaces"
            "custom/layout"
            "cffi/taskbar"
          ];
          modules-right = [
            "group/tray-drawer"
            "network"
            "bluetooth"
            "wireplumber"
          ]
          ++ lib.optional hasBattery "custom/battery"
          ++ [
            "clock"
            "custom/notification"
          ];

          # Each bar shows the 9 workspaces of *its* monitor, relabelled 1..9
          # (`format-icons`), while `hl.workspace_rule` keeps the workspace sets
          # independent: 1-9 on the first configured monitor, 10-18 on the
          # second, ... The two monitors are therefore unlinked: clicking tag N
          # on one bar switches that monitor only, and scrolling stays inside
          # the focused monitor's block. `all-outputs = false` (Waybar's default,
          # spelled out) is what keeps each bar to its own monitor's workspaces.
          # `move-to-monitor = false` keeps a click on `workspace <name>` (Waybar
          # 0.16 dispatches that itself, see Workspace::handleClicked) so the
          # workspace is switched on the monitor that owns it - the bar's own -
          # instead of being dragged onto the keyboard-focused one.
          "hyprland/workspaces" = {
            format = "{icon}";
            format-icons = workspaceIcons;
            all-outputs = false;
            move-to-monitor = false;
            on-click = "activate";
            on-scroll-up = cycleWorkspaceCmd 1;
            on-scroll-down = cycleWorkspaceCmd (-1);
            persistent-workspaces = persistentWorkspaces;
          };

          # AwesomeWM's `s.mylayoutbox`, right next to the taglist: shows the
          # active workspace's tiling layout and toggles master <-> dwindle on
          # click (SUPER+Space does the same and pokes `signal = 8` too).
          "custom/layout" = {
            exec = "${layoutScript}";
            signal = 8;
            tooltip = true;
            return-type = "json";
            escape = false;
            on-click = "${layoutScript} toggle";
          };

          # AwesomeWM's `mytasklist` via Waybar's native CFFI module API:
          # real per-app GTK icons from .desktop files / GtkIconTheme, strictly
          # filtered to the focused workspace's mapped windows plus the windows
          # minimized from that same workspace, direct click to focus/restore,
          # and width-bounded so workspaces and tray never overflow.
          "cffi/taskbar" = {
            module_path = "${waybarHyprTaskbar}/lib/libwaybar-hypr-taskbar.so";
            icon_size = 18;
            expand = true;
          };

          # System tray behind a click-to-reveal drawer: the bar only shows the
          # `custom/tray-toggle` chevron, and the tray icons slide out to its
          # left on a left click (Waybar 0.16 `group` drawer: the first entry of
          # `modules` is the leader, which is never hidden; `click-to-reveal`
          # makes the group toggle on click instead of on hover, so the bar
          # never shifts under the cursor).
          "group/tray-drawer" = {
            orientation = "inherit";
            modules = [
              "custom/tray-toggle"
              "tray"
            ];
            drawer = {
              transition-duration = 200;
              children-class = "tray-drawer-item";
              transition-left-to-right = false;
              click-to-reveal = true;
            };
          };

          # Static text only (no `exec`, no `interval`, no `signal`): Waybar
          # renders `format` as-is and never spawns a shell for it. The click
          # falls through to the group, which toggles the drawer.
          "custom/tray-toggle" = {
            format = "󰅃"; # md-chevron_up
            tooltip = true;
            tooltip-format = "System tray";
          };

          tray = {
            icon-size = 18;
            spacing = 6;
          };

          network = {
            interval = 5;
            format-wifi = "[↓{bandwidthDownBytes} ↑{bandwidthUpBytes}]";
            format-ethernet = "[E: ↓{bandwidthDownBytes} ↑{bandwidthUpBytes}]";
            format-disconnected = "[NET: down]";
            tooltip-format-wifi = "{essid} ({signalStrength}%) — {ipaddr}/{cidr}";
            tooltip-format-ethernet = "{ifname} — {ipaddr}/{cidr}";
            on-click = "${pkgs.kitty}/bin/kitty --class waybar-tui --title Network -e ${pkgs.networkmanager}/bin/nmtui";
          };

          # BlueZ controller state. `format-no-controller = ""` hides the module
          # completely on a machine without a Bluetooth adapter (jane-pc).
          bluetooth = {
            format = "[󰂯]"; # md-bluetooth
            format-connected = "[󰂱 {num_connections}]"; # md-bluetooth_connect
            format-on = "[󰂯]";
            format-off = "[󰂲]"; # md-bluetooth_off
            format-disabled = "[󰂲]";
            format-no-controller = "";
            tooltip-format = "{controller_alias} — {controller_address}";
            tooltip-format-connected = "{controller_alias} — {controller_address}\n\n{device_enumerate}";
            tooltip-format-enumerate-connected = "{device_alias} ({device_address})";
            tooltip-format-enumerate-connected-battery = "{device_alias} ({device_address}) {device_battery_percentage}%";
            on-click = "${pkgs.kitty}/bin/kitty --class waybar-tui --title Bluetooth -e ${pkgs.bluetui}/bin/bluetui";
            on-click-right = "${bluetoothToggleScript}";
          };

          # PipeWire sink volume through Waybar's native wireplumber module (it
          # is compiled in: the waybar binary links libwireplumber-0.5, so no
          # libpulse compatibility layer is involved). Scrolling is the
          # module's own volume control; `scroll-step = 5` is 5 % per notch on
          # its default `cubic_percent` scale.
          wireplumber = {
            format = "[󰕾 {volume}%]"; # md-volume_high
            format-muted = "[󰝟 MUTE]"; # md-volume_off
            format-bluetooth = "[󰂯 {volume}%]";
            format-bluetooth-muted = "[󰂲 MUTE]";
            tooltip-format = "{node_name} — {volume}%";
            scroll-step = 5;
            on-click = "${pkgs.pavucontrol}/bin/pavucontrol";
            on-click-right = "${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
          };

          clock = {
            interval = 1;
            format = "{:%a %b %d %H:%M:%S}";
            tooltip-format = "<tt>{calendar}</tt>";
          };

          # Swaync bell, far right. `swaync-client -swb` streams Waybar JSON
          # (`alt` = notification / none / dnd-* / inhibited-*, `text` = count,
          # `tooltip` = "N Notifications"), so the icon follows the daemon state
          # without polling. Left click toggles the control center, right click
          # toggles Do Not Disturb. The count is shown in the tooltip: a custom
          # module renders `{text}` verbatim, so embedding it in the glyph would
          # print "0" when the list is empty.
          "custom/notification" = {
            exec = "${pkgs.swaynotificationcenter}/bin/swaync-client -swb";
            return-type = "json";
            tooltip = true;
            format = "{icon}";
            format-icons = {
              notification = "[󰂚]"; # md-bell
              none = "[󰂜]"; # md-bell_outline
              dnd-notification = "[󰂛]"; # md-bell_off
              dnd-none = "[󰂛]";
              inhibited-notification = "[󰂚]";
              inhibited-none = "[󰂜]";
              dnd-inhibited-notification = "[󰂛]";
              dnd-inhibited-none = "[󰂛]";
            };
            on-click = "${pkgs.swaynotificationcenter}/bin/swaync-client -t -sw";
            on-click-right = "${pkgs.swaynotificationcenter}/bin/swaync-client -d -sw";
          };
        }
        # Desktops have no battery: no module, no config block.
        // lib.optionalAttrs hasBattery {
          # Waybar's `battery` module cannot report the charging protocol, so the
          # bar uses a `custom` module instead (see `batteryScript`). It emits the
          # text, CSS classes and tooltip itself and prints an empty `text` when
          # the machine has no battery, which `hide-empty-text` turns into a
          # fully hidden module.
          "custom/battery" = {
            exec = "${batteryScript}";
            # No `interval`: Waybar keeps the script running and reads JSON
            # lines from its stdout as they arrive. The script is event-driven
            # (a `power_supply` uevent socket, 15 s heartbeat) and prints only
            # when the rendered line changed, so there is no per-tick re-exec
            # and no timer wakeup - just one idle process in `select`.
            return-type = "json";
            tooltip = true;
            hide-empty-text = true;
          };
        };
      };

      style = ''
        * {
          border: none;
          border-radius: 0;
          font-family: "JetBrainsMono Nerd Font", monospace;
          font-size: 13.5px;
          min-height: 0;
        }

        window#waybar {
          background-color: #111111;
          color: #aaaaaa;
        }

        #workspaces {
          margin-left: 4px;
          min-width: 0;
        }

        #workspaces button {
          padding: 0 7px;
          min-width: 0;
          background-color: #111111;
          color: #aaaaaa;
        }

        #workspaces button.empty {
          color: #555555;
        }

        #workspaces button.active {
          background-color: #875fff;
          color: #ffffff;
        }

        #workspaces button.urgent {
          background-color: #d7ff5f;
          color: #111111;
        }

        #workspaces button:hover {
          background-color: #222222;
          color: #ffffff;
        }

        /* AwesomeWM mylayoutbox: `[master]` / `[dwindle]`, right of the tags. */
        #custom-layout {
          margin-left: 6px;
          padding: 0 7px;
          min-width: 0;
          background-color: #111111;
          color: #aaaaaa;
        }

        #custom-layout.master {
          color: #875fff;
        }

        #custom-layout:hover {
          background-color: #222222;
          color: #ffffff;
        }

        /* AwesomeWM mytasklist (CFFI GTK3 module): real per-app icons, focused
           workspace only (visible + minimized), self-bounded width so
           modules-left/right stay put. */
        #hypr-taskbar {
          padding: 0 2px;
          min-width: 0;
          background-color: transparent;
        }

        #hypr-taskbar button.task {
          padding: 0 8px;
          margin: 0;
          min-width: 0;
          min-height: 0;
          background-color: transparent;
          color: #aaaaaa;
          box-shadow: none;
          text-shadow: none;
        }

        #hypr-taskbar button.task:hover {
          background-color: #222222;
          color: #ffffff;
        }

        #hypr-taskbar button.task.active {
          background-color: #875fff;
          color: #ffffff;
        }

        /* Minimized windows of this workspace: still listed (left click
           restores + focuses, middle click minimizes a visible one) but dimmed
           so they read as "parked", not as another open window. */
        #hypr-taskbar button.task.minimized {
          color: #777777;
        }

        #hypr-taskbar button.task.minimized label {
          font-style: italic;
        }

        #hypr-taskbar button.task.minimized image {
          opacity: 0.55;
        }

        #hypr-taskbar button.task.minimized:hover {
          background-color: #222222;
          color: #aaaaaa;
        }

        #hypr-taskbar button.task label {
          min-width: 0;
        }

        #hypr-taskbar label.task-overflow {
          padding: 0 6px;
          color: #888888;
        }

        #tray,
        #network,
        #bluetooth,
        #wireplumber,
        #custom-battery,
        #custom-notification,
        #clock {
          padding: 0 4px;
          color: #aaaaaa;
        }

        /* System tray drawer: `custom/tray-toggle` is the always-visible group
           leader, the tray icons are its children (children-class
           `tray-drawer-item`) and slide out to its left. */
        #tray-drawer {
          padding: 0;
          margin: 0;
          background-color: transparent;
        }

        #custom-tray-toggle {
          padding: 0 6px;
          color: #aaaaaa;
        }

        #custom-tray-toggle:hover {
          background-color: #222222;
          color: #ffffff;
        }

        /* Muted sink / radio off: dim so it reads as "there, but inactive". */
        #wireplumber.muted {
          color: #555555;
        }

        #bluetooth.off,
        #bluetooth.disabled,
        #bluetooth.no-controller {
          color: #555555;
        }

        #bluetooth.connected {
          color: #875fff;
        }

        #clock {
          margin-right: 6px;
        }

        /* Swaync bell: dim when empty, purple with unread notifications,
           urgent yellow while Do Not Disturb is on (same signal colours as the
           workspace buttons). */
        #custom-notification {
          margin-right: 6px;
        }

        #custom-notification:hover {
          background-color: #222222;
          color: #ffffff;
        }

        #custom-notification.notification,
        #custom-notification.inhibited-notification {
          color: #875fff;
        }

        #custom-notification.dnd-none,
        #custom-notification.dnd-notification,
        #custom-notification.dnd-inhibited-none,
        #custom-notification.dnd-inhibited-notification {
          color: #d7ff5f;
        }

        #custom-notification.cc-open {
          color: #875fff;
        }

        /* Battery (`custom/battery`): the module's own classes say *why* it is
           charging, so the bar keeps one accent (purple) for anything powered by
           a real charger and dims "plugged but idle" states. */
        #custom-battery.charging {
          color: #c3a6ff;
        }

        #custom-battery.fast-charging,
        #custom-battery.pd,
        #custom-battery.pps,
        #custom-battery.qc {
          color: #875fff;
        }

        #custom-battery.wireless {
          color: #c3a6ff;
        }

        /* Plugged in, not charging (charge threshold / conservation mode). */
        #custom-battery.plugged {
          color: #8f8f8f;
        }

        #custom-battery.full {
          color: #875fff;
        }

        #custom-battery.warning:not(.charging) {
          color: #fad566;
        }

        #custom-battery.critical:not(.charging) {
          background-color: #d7ff5f;
          color: #111111;
        }
      '';
    };

    # Swaync notification daemon + control center (replaces mako). The HM module
    # ships a `Type=dbus` user unit (BusName=org.freedesktop.Notifications) bound
    # to graphical-session.target, so there is deliberately no
    # `hl.exec_cmd("swaync")` - that would start a second daemon.
    services.swaync = {
      enable = true;
      settings = {
        # The stylesheet below owns the whole look (AwesomeWM palette), so the
        # GTK theme must not leak in.
        ignore-gtk-theme = true;
        positionX = "right";
        positionY = "top";
        layer = "overlay";
        control-center-layer = "top";
        layer-shell = true;
        cssPriority = "user";
        # Sit under the 32px Waybar instead of covering it.
        control-center-margin-top = 40;
        control-center-margin-bottom = 10;
        control-center-margin-right = 10;
        control-center-margin-left = 10;
        control-center-width = 380;
        control-center-height = 640;
        notification-window-width = 380;
        notification-icon-size = 48;
        notification-body-image-height = 100;
        notification-body-image-width = 200;
        notification-2fa-action = true;
        notification-inline-replies = true;
        notification-grouping = true;
        timeout = 8;
        timeout-low = 4;
        timeout-critical = 0;
        transition-time = 180;
        hide-on-clear = false;
        hide-on-action = true;
        text-empty = "No notifications";
        keyboard-shortcuts = true;
        image-visibility = "when-available";
        fit-to-screen = true;
        relative-timestamps = true;
        widgets = [
          "title"
          "dnd"
          "buttons-grid"
          "mpris"
          "notifications"
        ];
        widget-config = {
          title = {
            text = "Notifications";
            clear-all-button = true;
            button-text = "Clear All";
          };
          dnd = {
            text = "Do Not Disturb";
          };
          notifications = {
            vexpand = true;
          };
          mpris = {
            blacklist = [ ];
            autohide = true;
            show-album-art = "always";
            loop-carousel = false;
          };
          buttons-grid = {
            buttons-per-row = 4;
            actions = [
              # Night Light: warm 4000K <-> neutral. `update-command` asks
              # hyprsunset itself, so the button also follows the automatic
              # 18:00-08:00 schedule.
              {
                label = "󰖔"; # md-weather_night
                type = "toggle";
                active = false;
                command = "${nightLightScript} toggle";
                update-command = "${nightLightScript} status";
              }
              {
                label = "󰖩"; # md-wifi
                command = "${pkgs.kitty}/bin/kitty --class waybar-tui --title Network -e ${pkgs.networkmanager}/bin/nmtui";
              }
              {
                label = "󰂯"; # md-bluetooth
                command = "${pkgs.kitty}/bin/kitty --class waybar-tui --title Bluetooth -e ${pkgs.bluetui}/bin/bluetui";
              }
              {
                label = "󰕾"; # md-volume_high
                command = "${pkgs.pavucontrol}/bin/pavucontrol";
              }
            ];
          };
        };
      };
      style = ''
        /* Swaync: AwesomeWM mytheme.lua palette (#000000 canvas, #111111
           surfaces, #875fff accent, #d7ff5f urgent), 6px corners,
           JetBrainsMono Nerd Font. */
        :root {
          --cc-bg: #111111;
          --noti-border-color: #222222;
          --noti-bg: 17, 17, 17;
          --noti-bg-alpha: 1;
          --noti-bg-darker: rgb(10, 10, 10);
          --noti-bg-hover: rgb(34, 34, 34);
          --noti-bg-focus: rgba(135, 95, 255, 0.25);
          --noti-close-bg: rgb(34, 34, 34);
          --noti-close-bg-hover: rgb(135, 95, 255);
          --text-color: rgb(255, 255, 255);
          --text-color-disabled: rgb(120, 120, 120);
          --bg-selected: rgb(135, 95, 255);
          --notification-icon-size: 48px;
          --notification-app-icon-size: 16px;
          --notification-group-icon-size: 24px;
          --border: 1px solid var(--noti-border-color);
          --border-radius: 6px;
          --notification-shadow: none;
          --font-size-body: 12px;
          --font-size-summary: 13px;
          --hover-transition: background 150ms ease-out;
          --mpris-album-art-overlay: rgba(0, 0, 0, 0.55);
          --mpris-button-hover: rgba(0, 0, 0, 0.5);
          --mpris-album-art-icon-size: 80px;
          --mpris-album-art-shadow: none;
        }

        * {
          font-family: "JetBrainsMono Nerd Font", monospace;
          font-size: 12px;
          outline: none;
          text-shadow: none;
        }

        notificationwindow,
        blankwindow {
          background: transparent;
        }

        /* ---- control center ---- */
        .control-center {
          background: var(--cc-bg);
          border: var(--border);
          border-radius: var(--border-radius);
          padding: 4px;
        }

        .control-center-list {
          background: transparent;
        }

        .control-center-list-placeholder {
          opacity: 0.5;
          color: var(--text-color-disabled);
        }

        .floating-notifications {
          background: transparent;
        }

        .floating-notifications .notification {
          box-shadow: var(--notification-shadow);
        }

        /* ---- notifications ---- */
        .notification-row {
          background: none;
          outline: none;
        }

        .notification-row .notification-background {
          padding: 4px 6px;
        }

        .notification-row .notification-background .notification {
          background: var(--noti-bg-darker);
          border: var(--border);
          border-radius: var(--border-radius);
          padding: 0;
          transition: var(--hover-transition);
        }

        .notification-row .notification-background .notification.critical {
          border-color: #d7ff5f;
        }

        .notification-row .notification-background .notification .notification-default-action {
          background: transparent;
          border: none;
          border-radius: var(--border-radius);
          box-shadow: none;
          color: var(--text-color);
          margin: 0;
          padding: 6px;
          transition: var(--hover-transition);
        }

        .notification-row .notification-background .notification .notification-default-action:hover {
          background: var(--noti-bg-hover);
        }

        .notification-row .notification-background .notification .notification-default-action:not(:only-child) {
          border-bottom-left-radius: 0;
          border-bottom-right-radius: 0;
        }

        .notification-row .notification-background .notification .notification-default-action .notification-content {
          background: transparent;
          border-radius: var(--border-radius);
          padding: 0;
        }

        .notification-row .notification-background .notification .notification-default-action .notification-content .image {
          -gtk-icon-filter: none;
          -gtk-icon-size: var(--notification-icon-size);
          border-radius: var(--border-radius);
          margin: 4px;
        }

        .notification-row .notification-background .notification .notification-default-action .notification-content .app-icon {
          -gtk-icon-filter: none;
          -gtk-icon-size: var(--notification-app-icon-size);
          margin: 6px;
        }

        .notification-row .notification-background .notification .notification-default-action .notification-content .text-box label {
          filter: none;
        }

        .notification-row .notification-background .notification .notification-default-action .notification-content .text-box .summary {
          background: transparent;
          color: var(--text-color);
          font-size: var(--font-size-summary);
          font-weight: bold;
        }

        .notification-row .notification-background .notification .notification-default-action .notification-content .text-box .time {
          background: transparent;
          color: var(--text-color-disabled);
          font-size: var(--font-size-summary);
          font-weight: bold;
          margin-right: 30px;
        }

        .notification-row .notification-background .notification .notification-default-action .notification-content .text-box .body {
          background: transparent;
          color: var(--text-color);
          font-size: var(--font-size-body);
          font-weight: normal;
        }

        .notification-row .notification-background .notification .notification-default-action .notification-content progressbar {
          margin-top: 4px;
        }

        .notification-row .notification-background .notification .notification-default-action .notification-content .inline-reply {
          margin-top: 4px;
        }

        .notification-row .notification-background .notification .notification-default-action .notification-content .inline-reply .inline-reply-entry {
          background: #111111;
          border: var(--border);
          border-radius: var(--border-radius);
          caret-color: var(--text-color);
          color: var(--text-color);
        }

        .notification-row .notification-background .notification .notification-default-action .notification-content .inline-reply .inline-reply-button {
          background: var(--noti-bg-hover);
          border: var(--border);
          border-radius: var(--border-radius);
          color: var(--text-color);
          margin-left: 4px;
        }

        .notification-row .notification-background .notification .notification-alt-actions {
          background: none;
          border-bottom-left-radius: var(--border-radius);
          border-bottom-right-radius: var(--border-radius);
          padding: 4px;
        }

        .notification-row .notification-background .notification .notification-action {
          margin: 4px;
          padding: 0;
        }

        .notification-row .notification-background .notification .notification-action > button {
          border-radius: var(--border-radius);
          color: var(--text-color);
        }

        .notification-group {
          transition: opacity 180ms ease-out;
        }

        .notification-group:focus {
          background: var(--noti-bg-focus);
        }

        .notification-group.collapsed.not-expanded {
          opacity: 0.4;
        }

        .notification-group.collapsed .notification-row .notification {
          background-color: rgba(var(--noti-bg), 1);
        }

        .notification-group.collapsed .notification-row:not(:last-child) .notification-action,
        .notification-group.collapsed .notification-row:not(:last-child) .notification-default-action {
          opacity: 0;
        }

        .notification-group.collapsed:hover .notification-row:not(:only-child) .notification {
          background-color: var(--noti-bg-hover);
        }

        .notification-group .notification-group-buttons,
        .notification-group .notification-group-headers {
          color: var(--text-color);
          margin: 0 12px;
        }

        .notification-group .notification-group-headers .notification-group-icon {
          -gtk-icon-size: var(--notification-group-icon-size);
          color: var(--text-color);
        }

        .notification-group .notification-group-headers .notification-group-header {
          color: var(--text-color);
        }

        .notification-group .notification-group-close-button .close-button {
          margin: 10px 16px;
        }

        .close-button {
          background: var(--noti-close-bg);
          border: none;
          border-radius: var(--border-radius);
          box-shadow: none;
          color: var(--text-color-disabled);
          margin: 6px;
          min-height: 20px;
          min-width: 20px;
          padding: 0;
          transition: var(--hover-transition);
        }

        .close-button:hover {
          background: var(--noti-close-bg-hover);
          color: var(--text-color);
        }

        /* ---- widgets ---- */
        .widget {
          background: transparent;
          border-radius: var(--border-radius);
          margin: 4px;
          padding: 4px;
        }

        .widget-title > label {
          color: #875fff;
          font-size: 1.2rem;
          margin-right: 6px;
        }

        .widget-title > button {
          background: #1b1b1b;
          border: 1px solid #262626;
          border-radius: var(--border-radius);
          color: var(--text-color);
          margin-left: 6px;
          padding: 2px 10px;
          transition: var(--hover-transition);
        }

        .widget-title > button:hover {
          background: #875fff;
          border-color: #875fff;
        }

        .widget-dnd > label {
          color: var(--text-color);
          font-size: 1rem;
          margin-right: 6px;
        }

        .widget-dnd > switch {
          background: #222222;
          border-radius: var(--border-radius);
        }

        .widget-dnd > switch:checked {
          background: #875fff;
        }

        .widget-dnd > switch slider {
          background: #ffffff;
          border-radius: var(--border-radius);
          min-height: 16px;
          min-width: 16px;
        }

        .widget-buttons-grid > flowbox > flowboxchild > button {
          background: #1b1b1b;
          border: 1px solid #262626;
          border-radius: var(--border-radius);
          color: #dddddd;
          min-height: 32px;
          padding: 6px 2px;
          transition: var(--hover-transition);
        }

        .widget-buttons-grid > flowbox > flowboxchild > button:hover {
          background: #222222;
          color: var(--text-color);
        }

        .widget-buttons-grid > flowbox > flowboxchild > button.toggle:checked {
          background: #875fff;
          border-color: #875fff;
          color: var(--text-color);
        }

        .widget-mpris {
          padding: 0;
        }

        .widget-mpris .widget-mpris-player {
          border-radius: var(--border-radius);
          box-shadow: var(--mpris-album-art-shadow);
          margin: 8px;
        }

        .widget-mpris .widget-mpris-player .mpris-overlay {
          background-color: var(--mpris-album-art-overlay);
          padding: 10px;
        }

        .widget-mpris .widget-mpris-player .mpris-overlay button:hover {
          background: var(--noti-bg-hover);
        }

        .widget-mpris .widget-mpris-player .mpris-overlay .widget-mpris-album-art {
          -gtk-icon-size: var(--mpris-album-art-icon-size);
          border-radius: var(--border-radius);
          box-shadow: var(--mpris-album-art-shadow);
        }

        .widget-mpris .widget-mpris-player .mpris-overlay .widget-mpris-title {
          color: var(--text-color);
          font-size: 1.1rem;
          font-weight: bold;
        }

        .widget-mpris .widget-mpris-player .mpris-overlay .widget-mpris-subtitle {
          color: var(--text-color-disabled);
          font-size: 0.95rem;
        }

        .widget-mpris .widget-mpris-player .mpris-overlay > box > button:hover {
          background-color: var(--mpris-button-hover);
        }
      '';
    };

    # SwayOSD: volume / brightness / caps-lock on-screen display. The server is a
    # systemd user unit from the HM module (graphical-session.target), the
    # clients are called from volumeScript, brightnessScript and the Caps_Lock
    # bind - no `hl.exec_cmd` needed here either.
    services.swayosd = {
      enable = true;
      stylePath = swayosdStyle;
    };

    # Hyprsunset: automatic night light. The HM module writes
    # `~/.config/hypr/hyprsunset.conf` and runs hyprsunset as a user unit, which
    # applies the profile for the current time on start and re-applies it at
    # every boundary. 18:00-08:00 is warm (4000K), the rest of the day neutral.
    services.hyprsunset = {
      enable = true;
      settings = {
        max-gamma = 100;
        profile = [
          {
            time = "08:00";
            identity = true;
          }
          {
            time = "18:00";
            temperature = 4000;
          }
        ];
      };
    };

    # Hyprlock matching i3lock -c 000000 + mytheme.lua palette (PAM configured in modules/hyprland.nix)
    programs.hyprlock = {
      enable = true;
      package = null;
      settings = {
        general = {
          hide_cursor = true;
          # false so an empty Enter still reaches PAM and triggers the
          # YubiKey touch (true swallows the keypress entirely).
          ignore_empty_input = false;
        };

        background = [
          {
            monitor = "";
            color = "rgb(0, 0, 0)";
          }
        ];

        label = [
          {
            monitor = "";
            text = "$TIME";
            color = "rgb(170, 170, 170)";
            font_size = 36;
            font_family = "JetBrainsMono Nerd Font";
            position = "0, 80";
            halign = "center";
            valign = "center";
          }
        ];

        input-field = [
          {
            monitor = "";
            size = "260, 44";
            outline_thickness = 3;
            dots_size = 0.25;
            dots_spacing = 0.25;
            outer_color = "rgb(135, 95, 255)";
            inner_color = "rgb(17, 17, 17)";
            font_color = "rgb(255, 255, 255)";
            check_color = "rgb(215, 255, 95)";
            fail_color = "rgb(240, 94, 72)";
            fade_on_empty = false;
            # Matches decoration.rounding (subtle 6px).
            rounding = 6;
            placeholder_text = "Password / Touch YubiKey";
            position = "0, 0";
            halign = "center";
            valign = "center";
          }
        ];
      };
    };

    # Hypridle: lock on suspend on every host (replaces modules/lock.nix on
    # X11); the idle lock/DPMS timeouts are per-host (null = disabled).
    services.hypridle = {
      enable = true;
      package = null;
      settings = {
        general = {
          lock_cmd = "pidof hyprlock || hyprlock";
          # Runs right before suspend (power button / `systemctl suspend`), so
          # `s2idle` never resumes into a still-playing player.
          before_sleep_cmd = "${pauseMediaCmd}; loginctl lock-session";
          after_sleep_cmd = "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'";
        };
      }
      // lib.optionalAttrs (hypridleListeners != [ ]) {
        listener = hypridleListeners;
      };
    };
  };
}
