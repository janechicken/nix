# Home Manager module for Hyprland (0.57+ Lua config) matching the AwesomeWM
# look & feel (dotfiles/awesome/rc.lua + mytheme.lua + picom.conf + rofi/simple.rasi):
#   - Pure #000000 OLED wallpaper, #111111 surfaces, #875fff purple focus, #d7ff5f urgent
#   - Sharp corners (rounding = 0), 3px borders, 5px inner / 10px outer gaps, subtle shadows
#   - Top Waybar mirroring Awesome's wibar (tags 1-9, layout box, tasklist,
#     tray, net, bat, mem, clock); the tasklist is a socket2-driven
#     `cffi/taskbar` (focused workspace only, visible *and* minimized windows,
#     width-bounded) and the layout box a clickable `custom/layout`
#     (`[master]` / `[dwindle]`)
#   - AwesomeWM keybinds, master (tile, default) <-> dwindle (spiral) toggle, sloppy focus
#   - hyprbars titlebars on floating windows only (AwesomeWM draws them on floats)
#   - Window minimize/restore via the hidden special:minimized workspace, tagged
#     per originating workspace (`minimized-ws-<N>`) so the taskbar can list a
#     workspace's minimized windows; keyboard + mouse resizing (resizeactive on
#     tiled and floating windows)
#   - Mako bottom-right notifications, Hyprlock (#000000 + U2F), Hypridle lid/sleep lock
#
# Shared by every Hyprland host (hosts/<host>/home.nix). Hosts configure
# `custom.hyprland.*`; everything else (keybinds, Waybar, Mako, Hyprlock) is
# byte-identical so the two machines look and behave the same. Only these
# hardware facts differ:
#   monitors / isLaptop / batteryName / vrr / idleLockTimeout / idleDpmsTimeout
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.custom.hyprland;

  # Workspaces are bounded to 1..9, matching AwesomeWM's tags 1-9.
  workspaceCount = 9;

  volumeScript = pkgs.writeShellScript "hypr-volume" ''
    set -euo pipefail
    action="''${1:-}"
    case "$action" in
      up)
        ${pkgs.wireplumber}/bin/wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+
        title="Volume up"
        ;;
      down)
        ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
        title="Volume down"
        ;;
      mute)
        ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
        title="Toggle mute"
        ;;
      *)
        exit 1
        ;;
    esac

    out="$(${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SINK@)"
    if echo "$out" | grep -q '\[MUTED\]'; then
      body="Muted"
    else
      pct="$(echo "$out" | awk '{ printf "%d", ($2 * 100) + 0.5 }')"
      body="Volume: ''${pct}%"
    fi

    ${pkgs.libnotify}/bin/notify-send \
      -a volume \
      -h string:x-canonical-private-synchronous:volume \
      -t 2000 \
      "$title" "$body"
  '';

  brightnessScript = pkgs.writeShellScript "hypr-brightness" ''
    set -euo pipefail
    action="''${1:-}"
    # Floor at 5% (-n5%) to prevent ATNA40CT03-0 OLED eDP backlight from ever hitting 0.
    case "$action" in
      up)
        ${pkgs.brightnessctl}/bin/brightnessctl -e4 -n5% set 5%+ >/dev/null
        title="Brightness up"
        ;;
      down)
        ${pkgs.brightnessctl}/bin/brightnessctl -e4 -n5% set 5%- >/dev/null
        title="Brightness down"
        ;;
      *)
        exit 1
        ;;
    esac

    pct="$(${pkgs.brightnessctl}/bin/brightnessctl -m | cut -d, -f4)"
    ${pkgs.libnotify}/bin/notify-send \
      -a brightness \
      -h string:x-canonical-private-synchronous:brightness \
      -t 2000 \
      "$title" "Brightness: ''${pct}"
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

  # Waybar scroll handler: the same 1..9 wrap-around as `cycle_workspace`
  # below, evaluated by Hyprland's own Lua runtime through `hyprctl dispatch`.
  # `r+1`/`r-1` must never be used here: a single trackpad scroll would spawn
  # workspaces 10, 11, 12, ...
  cycleWorkspaceCmd =
    delta:
    "hyprctl dispatch \"hl.dsp.focus({workspace = ((hl.get_active_workspace().id - 1 + (${toString delta})) % ${toString workspaceCount}) + 1})\"";

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
        rounding = 0,
        active_opacity = 1.0,
        inactive_opacity = 1.0,
        shadow = {
          enabled = true,
          range = 7,
          render_power = 3,
          color = "rgba(000000bb)",
        },
        blur = {
          enabled = false,
        },
      },

      animations = {
        enabled = false,
      },

      dwindle = {
        force_split = 2,
        preserve_split = true,
      },

      master = {
        mfact = 0.55,
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
        -- 0 = off, 1 = on, 2 = fullscreen only
        vrr = ${toString cfg.vrr},
      },

      xwayland = {
        force_zero_scaling = true,
      },

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
    ${lib.optionalString cfg.isLaptop ''
      -- 3-finger horizontal swipe to switch workspaces on the touchpad.
      -- workspace_swipe_create_new would otherwise create workspace 10, 11, ...
      -- when swiping right from the last workspace (Hyprland default: true).
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
      hl.exec_cmd("mako")
      hl.exec_cmd("copyq")
      hl.exec_cmd("udiskie --tray")
      -- Flameshot daemon (tray icon + the screenshot backend used by Print)
      hl.exec_cmd("flameshot")
    end)

    ---------------------------
    ---- WORKSPACE CYCLING ----
    ---------------------------
    -- Workspaces stay inside 1..9 (AwesomeWM tags). Hyprland's relative
    -- selectors (r+1 / r-1) create workspace 10, 11, ... on every scroll.
    local WORKSPACE_COUNT = ${toString workspaceCount}

    local function cycle_workspace(delta)
      local ws = hl.get_active_workspace()
      local id = ws and ws.id or 1
      if id < 1 or id > WORKSPACE_COUNT then
        id = 1
      end
      hl.dispatch(hl.dsp.focus({ workspace = ((id - 1 + delta) % WORKSPACE_COUNT) + 1 }))
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

    -- Windows that become floating later: SUPER+CTRL+Space, Flameshot pins,
    -- `setprop floating`, plugin/mouse rules. Pinned windows (Flameshot's
    -- screenshots) place themselves and are left alone.
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

    -- Workspace navigation, bounded to 1..9 (wrapping like AwesomeWM's tags)
    hl.bind(mainMod .. " + Left", function() cycle_workspace(-1) end, { description = "previous workspace" })
    hl.bind(mainMod .. " + Right", function() cycle_workspace(1) end, { description = "next workspace" })
    hl.bind(mainMod .. " + Escape", hl.dsp.focus({ workspace = "previous" }), { description = "restore previous workspace" })

    for i = 1, 9 do
      hl.bind(mainMod .. " + " .. i, hl.dsp.focus({ workspace = i }), { description = "workspace " .. i })
      hl.bind(
        mainMod .. " + SHIFT + " .. i,
        hl.dsp.window.move({ workspace = i, follow = false }),
        { description = "move window to workspace " .. i }
      )
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

    -- hyprbars buttons run a shell command, so the titlebar minimize button
    -- carries its own self-contained copy of `minimize_active`.
    local HYPRBARS_MINIMIZE = "hyprctl dispatch 'function() local w = hl.get_active_window() if not w then return end "
      .. "local ws = hl.get_active_workspace() if ws.special then ws = hl.get_last_workspace() end if not ws then return end "
      .. "hl.dispatch(hl.dsp.window.clear_tags({ window = w })) "
      .. "hl.dispatch(hl.dsp.window.tag({ tag = \"minimized-ws-\" .. tostring(ws.id), window = w })) "
      .. "hl.dispatch(hl.dsp.window.move({ workspace = \"special:minimized\", follow = false, window = w })) end'"

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
    hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
    ${lib.optionalString cfg.isLaptop ''
      -- Panel backlight (laptops only; desktops have no brightness device)
      hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("${brightnessScript} up"), { locked = true, repeating = true })
      hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("${brightnessScript} down"), { locked = true, repeating = true })

      -- Lid switch (laptops only). logind handles the lock itself
      -- (`HandleLidSwitch = lock` -> hypridle runs lock_cmd), this also mutes the
      -- speakers and powers the panel down so nothing lights up in a bag.
      -- The device name comes from libinput (Aquamarine uses it verbatim):
      -- most laptops expose "Lid Switch", the Yoga Slim 7 reports "gpio-keys".
      hl.bind("switch:on:${cfg.lidSwitchName}", function()
        hl.dispatch(hl.dsp.exec_cmd("${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ 1; pidof hyprlock || hyprlock"))
        hl.dispatch(hl.dsp.dpms(${lidDpmsOff}))
      end, { locked = true, description = "lid close: mute, lock, panel off" })

      -- Lid open: panel back on. Mute is deliberately not undone.
      hl.bind("switch:off:${cfg.lidSwitchName}", function()
        hl.dispatch(hl.dsp.dpms({ action = "enable" }))
      end, { locked = true, description = "lid open: panel on" })
    ''}
    -- Screenshots (Flameshot, Wayland-native via xdg-desktop-portal; `--clipboard`
    -- copies and `saveAfterCopy` in flameshot.ini also saves to ~/Pictures/Screenshots)
    hl.bind("Print", hl.dsp.exec_cmd("flameshot screen --clipboard"), { description = "screenshot monitor" })
    hl.bind("CONTROL + Print", hl.dsp.exec_cmd("flameshot gui --clipboard"), { description = "screenshot selection" })

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

    -- Flameshot: its capture overlay, pinned screenshots and settings window are
    -- plain xdg_toplevels, so Hyprland has to float/pin them itself (Wayland has
    -- no "always on top" hint). Without this the overlay gets tiled into the
    -- layout and pinned screenshots end up behind other windows.
    -- No `center`/`move` (Flameshot places pins itself) and no `stay_focused`
    -- (it would block focusing any other window while a pin exists).
    hl.window_rule({
      name = "flameshot",
      match = { class = "^(flameshot|org\\.flameshot\\.Flameshot)$" },
      float = true,
      pin = true,
      no_anim = true,
      border_size = 0,
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
            bar_text_align = "left",
            bar_buttons_alignment = "right",
            bar_padding = 8,
            bar_button_padding = 6,
            bar_part_of_window = true,
            bar_blur = false,
            -- 0 (fully transparent) disables hyprbars' inactive-button recolouring,
            -- so the buttons keep their own (transparent) background and only the
            -- glyph is drawn on both the focused and the unfocused bar.
            inactive_button_color = "rgba(00000000)",
            on_double_click = "hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = \"maximized\" })'",
          },
        },
      })

      -- Buttons are drawn right to left, so the first entry is the rightmost one.
      -- `size` is the button box (the glyph is drawn at ~0.62 * size), and a
      -- transparent background keeps only the glyph visible.
      if hl.plugin.hyprbars and hl.plugin.hyprbars.add_button then
        hl.plugin.hyprbars.add_button({
          bg_color = "rgba(00000000)",
          fg_color = "rgb(ffffff)",
          size = 18,
          icon = "×",
          action = "hyprctl dispatch 'hl.dsp.window.close()'",
        })
        hl.plugin.hyprbars.add_button({
          bg_color = "rgba(00000000)",
          fg_color = "rgb(ffffff)",
          size = 18,
          icon = "□",
          action = "hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = \"maximized\" })'",
        })
        hl.plugin.hyprbars.add_button({
          bg_color = "rgba(00000000)",
          fg_color = "rgb(ffffff)",
          size = 18,
          icon = "—",
          action = HYPRBARS_MINIMIZE,
        })
      end

      -- AwesomeWM draws titlebars on floating clients only: hyprbars decorates
      -- every window, so tiled clients, Flameshot's capture overlay / pinned
      -- screenshots and the invisible XWayland drag proxies get `no_bar`.
      hl.window_rule({
        name = "hyprbars-tiled",
        match = { float = false },
        ["hyprbars:no_bar"] = true,
      })
      hl.window_rule({
        name = "hyprbars-flameshot",
        match = { class = "^(flameshot|org\\.flameshot\\.Flameshot)$" },
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
        Battery device name for Waybar (`bat`). When null and `isLaptop` is
        false, no battery module is shown at all.
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
        # grim is not used by Flameshot 15 (it captures through
        # xdg-desktop-portal) but is kept for ad-hoc screencopy/scripting.
        grim
        libnotify
      ]
      ++ lib.optional cfg.isLaptop brightnessctl;

    # Cursor theme for GTK, XWayland, and native Hyprland (hyprcursor)
    home.pointerCursor = {
      enable = true;
      gtk.enable = true;
      hyprcursor.enable = true;
    };

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
          modules-left = [
            "hyprland/workspaces"
            "custom/layout"
          ];
          modules-center = [ "cffi/taskbar" ];
          modules-right = [
            "tray"
            "network"
          ]
          ++ lib.optional hasBattery "battery"
          ++ [
            "memory"
            "clock"
          ];

          "hyprland/workspaces" = {
            format = "{id}";
            on-click = "activate";
            # Bounded 1..9 wrap-around (same as SUPER+Left/Right); scrolling
            # must never create workspace 10+.
            on-scroll-up = cycleWorkspaceCmd 1;
            on-scroll-down = cycleWorkspaceCmd (-1);
            persistent-workspaces = {
              "*" = workspaceCount;
            };
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
          };

          memory = {
            interval = 5;
            format = "[{used:0.1f}Gi]";
            tooltip-format = "{used:0.1f}GiB / {total:0.1f}GiB ({percentage}%)";
          };

          clock = {
            interval = 1;
            format = "{:%a %b %d %H:%M:%S}";
            tooltip-format = "<tt>{calendar}</tt>";
          };
        }
        # Desktops have no battery: no module, no config block.
        // lib.optionalAttrs hasBattery {
          # `bat` is only pinned where the kernel device name is non-standard.
          battery = {
            interval = 5;
            states = {
              warning = 20;
              critical = 10;
            };
            format = "[{capacity}% BAT]";
            format-charging = "[{capacity}% BAT ↑]";
            format-discharging = "[{capacity}% BAT ↓]";
            format-plugged = "[{capacity}% BAT]";
            tooltip-format = "{timeTo} ({power}W)";
          }
          // lib.optionalAttrs (cfg.batteryName != null) {
            bat = cfg.batteryName;
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
        #battery,
        #memory,
        #clock {
          padding: 0 4px;
          color: #aaaaaa;
        }

        #clock {
          margin-right: 6px;
        }

        #battery.warning:not(.charging) {
          color: #fad566;
        }

        #battery.critical:not(.charging) {
          background-color: #d7ff5f;
          color: #111111;
        }
      '';
    };

    # Mako notifications matching AwesomeWM naughty + mytheme.lua
    services.mako = {
      enable = true;
      settings = {
        font = "JetBrainsMono Nerd Font 11";
        anchor = "bottom-right";
        background-color = "#111111";
        text-color = "#ffffff";
        border-color = "#875fff";
        border-size = 3;
        border-radius = 0;
        padding = "8,10";
        margin = "10";
        max-icon-size = 32;
        default-timeout = 10000;
        "urgency=critical" = {
          background-color = "#900000";
          border-color = "#d7ff5f";
          default-timeout = 0;
        };
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
            rounding = 0;
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
          before_sleep_cmd = "loginctl lock-session";
          after_sleep_cmd = "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'";
        };
      }
      // lib.optionalAttrs (hypridleListeners != [ ]) {
        listener = hypridleListeners;
      };
    };
  };
}
