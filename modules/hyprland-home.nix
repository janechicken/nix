# Home Manager module for Hyprland (0.57+ Lua config) matching the AwesomeWM
# look & feel (dotfiles/awesome/rc.lua + mytheme.lua + picom.conf + rofi/simple.rasi):
#   - Pure #000000 OLED wallpaper, #111111 surfaces, #875fff purple focus, #d7ff5f urgent
#   - Sharp corners (rounding = 0), 3px borders, 5px inner / 10px outer gaps, subtle shadows
#   - Top Waybar mirroring Awesome's wibar (tags 1-9, window tasklist, tray, net, bat, mem, clock)
#   - AwesomeWM keybinds, dwindle (spiral) <-> master (tile) toggle, sloppy focus
#   - hyprbars titlebars on floating windows only (AwesomeWM draws them on floats)
#   - Window minimize/restore via the hidden special:minimized workspace,
#     keyboard + mouse resizing (resizeactive on tiled and floating windows)
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
        layout = "dwindle",
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

    -- Layout manipulation (dwindle <-> master, split ratio / mfact).
    -- `mfact` / `splitratio` are layout-only and take *relative* deltas, so
    -- floating windows fall back to a plain resize instead of doing nothing.
    local function adjust_split(delta)
      local win = hl.get_active_window()
      if win and win.floating then
        resize_active(math.floor(delta * 800), 0)
        return
      end
      local layout = hl.get_config("general.layout")
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

    hl.bind(mainMod .. " + space", function()
      local cur = hl.get_config("general.layout")
      local next_layout = (cur == "dwindle") and "master" or "dwindle"
      hl.config({ general = { layout = next_layout } })
    end, { description = "toggle dwindle / master layout" })

    -- Client states (matching AwesomeWM: G=fullscreen, M=maximize, Ctrl+Space=float, Ctrl+Return=master, O=screen, T=pin)
    hl.bind(mainMod .. " + G", hl.dsp.window.fullscreen({ mode = "fullscreen" }), { description = "toggle fullscreen" })
    hl.bind(mainMod .. " + M", hl.dsp.window.fullscreen({ mode = "maximized" }), { description = "toggle maximize" })
    hl.bind(mainMod .. " + CONTROL + space", function()
      hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
      local win = hl.get_active_window()
      if win and win.floating then
        hl.dispatch(hl.dsp.window.center())
      end
    end, { description = "toggle floating (centered)" })
    -- `swapwithmaster` is a master-only layoutmsg: on dwindle Hyprland answers
    -- "Unknown dwindle layoutmsg" and nothing happens. dwindle's equivalent is
    -- `movetoroot`, which promotes the focused window to the root (master) slot.
    local function swap_with_master()
      if hl.get_config("general.layout") == "master" then
        hl.dispatch(hl.dsp.layout("swapwithmaster"))
      else
        hl.dispatch(hl.dsp.layout("movetoroot"))
      end
    end

    hl.bind(mainMod .. " + CONTROL + Return", swap_with_master, { description = "swap with master" })
    hl.bind(mainMod .. " + O", hl.dsp.window.move({ monitor = "+1" }), { description = "move window to next monitor" })
    hl.bind(mainMod .. " + T", hl.dsp.window.pin(), { description = "toggle pin / keep on top (floating)" })

    -- Minimize / restore (matching dotfiles/awesome/rc.lua modkey+n / modkey+Control+n).
    -- Minimized clients are parked on the hidden "special:minimized" workspace;
    -- the stack below keeps the LIFO order so restore pops the newest one.
    local minimized = {}

    local function minimize_active()
      local win = hl.get_active_window()
      if not win then
        return
      end
      if win.workspace and win.workspace.name == "special:minimized" then
        return
      end
      minimized[#minimized + 1] = {
        address = win.address,
        workspace = win.workspace and win.workspace.id or nil,
      }
      hl.dispatch(hl.dsp.window.move({ workspace = "special:minimized", follow = false }))
    end

    local function restore_minimized()
      -- Capture the destination first: focusing a hidden window would otherwise
      -- make the special workspace the active one.
      local target = hl.get_active_workspace()
      if target and target.special then
        target = hl.get_last_workspace()
      end
      local target_id = target and target.id or nil

      local win
      while #minimized > 0 do
        local entry = table.remove(minimized)
        local candidate = hl.get_window("address:" .. entry.address)
        if candidate and candidate.workspace and candidate.workspace.name == "special:minimized" then
          win = candidate
          -- Prefer the workspace we are on, else the one it came from.
          target_id = target_id or entry.workspace
          break
        end
      end
      if not win then
        -- Stack empty or stale (e.g. after a config reload): take anything left.
        local hidden = hl.get_windows({ workspace = "special:minimized" })
        win = hidden[#hidden]
      end
      if not win then
        return
      end

      hl.dispatch(hl.dsp.focus({ window = win }))
      hl.dispatch(hl.dsp.window.move({ workspace = target_id or "e+0", follow = true }))
      -- Make sure the restored window really ends up focused (e.g. when the
      -- special workspace is being peeked at while restoring).
      hl.dispatch(hl.dsp.focus({ window = win }))
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
          action = "hyprctl dispatch 'hl.dsp.window.move({ workspace = \"special:minimized\", follow = false })'",
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
          height = 24;
          spacing = 6;
          modules-left = [ "hyprland/workspaces" ];
          modules-center = [ "wlr/taskbar" ];
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

          # AwesomeWM's `mytasklist`: every window of the current output as a
          # clickable button (Waybar 0.16's wlr/taskbar has no workspace filter,
          # `all-outputs = false` is the closest scope). Needs
          # zwlr_foreign_toplevel_manager_v1, which Hyprland 0.57 advertises.
          "wlr/taskbar" = {
            format = "{icon} {title:.24}";
            icon-size = 14;
            tooltip = true;
            tooltip-format = "{title}";
            all-outputs = false;
            on-click = "activate";
            on-click-middle = "close";
          };

          tray = {
            icon-size = 16;
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
          font-size: 13px;
          min-height: 0;
        }

        window#waybar {
          background-color: #111111;
          color: #aaaaaa;
        }

        #workspaces {
          margin-left: 4px;
        }

        #workspaces button {
          padding: 0 6px;
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

        /* AwesomeWM mytasklist: dark surface, purple active button, dimmed minimized. */
        #taskbar {
          padding: 0 6px;
          background-color: transparent;
        }

        #taskbar button {
          padding: 0 6px;
          background-color: #111111;
          color: #aaaaaa;
          border-radius: 0;
        }

        #taskbar button.active {
          background-color: #875fff;
          color: #ffffff;
        }

        #taskbar button.minimized {
          color: #555555;
        }

        #taskbar button:hover {
          background-color: #222222;
          color: #ffffff;
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
          ignore_empty_input = true;
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
