-- If LuaRocks is installed, make sure that packages installed through it are
-- found (e.g. lgi). If LuaRocks is not installed, do nothing.
pcall(require, "luarocks.loader")

-- Standard awesome library
local gears = require("gears")
local awful = require("awful")
require("awful.autofocus")
-- Widget and layout library
local wibox = require("wibox")
-- Theme handling library
local beautiful = require("beautiful")
-- Notification library
local naughty = require("naughty")
local menubar = require("menubar")
local hotkeys_popup = require("awful.hotkeys_popup")
-- local vicious = require("vicious")
-- Enable hotkeys help widget for VIM and other apps
-- when client with a matching name is opened:
require("awful.hotkeys_popup.keys")


-- notification config
naughty.config.defaults.ontop = true
-- naughty.config.defaults.icon_size = dpi(32)
naughty.config.defaults.screen = awful.screen.focused()
naughty.config.defaults.timeout = 10
naughty.config.defaults.title = "System Notification"
naughty.config.defaults.position = "bottom_right"
naughty.config.presets.low.timeout = 10
naughty.config.presets.critical.timeout = 0
naughty.config.presets.ok = naughty.config.presets.normal
naughty.config.presets.info = naughty.config.presets.normal
naughty.config.presets.warn = naughty.config.presets.critical
beautiful.notification_max_width = 10

--fullscren fix

--autostart
autorun = true
autorunApps = {
  "equibop",
  "arrpc",
  "signal-desktop",
  "copyq",
  "keepassxc",
  "udiskie",
  "copyq",
  "flameshot",
  "easyeffects --gapplication-service",
}


client.connect_signal("request::manage", function(client, context)
  if client.floating and context == "new" then
    client.placement = awful.placement.centered
  end
end)

-- {{{ Error handling
-- Check if awesome encountered an error during startup and fell back to
-- another config (This code will only ever execute for the fallback config)
if awesome.startup_errors then
  naughty.notify({
    preset = naughty.config.presets.critical,
    title = "Oops, there were errors during startup!",
    text = awesome.startup_errors
  })
end

-- Handle runtime errors after startup
do
  local in_error = false
  awesome.connect_signal("debug::error", function(err)
    -- Make sure we don't go into an endless error loop
    if in_error then return end
    in_error = true

    naughty.notify({
      preset = naughty.config.presets.critical,
      title = "Oops, an error happened!",
      text = tostring(err)
    })
    in_error = false
  end)
end
-- }}}

-- {{{ Variable definitions
-- Themes define colours, icons, font and wallpapers.
beautiful.init(gears.filesystem.get_configuration_dir() .. "mytheme.lua")


if autorun then
  for app = 1, #autorunApps do
    awful.util.spawn(autorunApps[app])
  end
end

-- margin widget for spacing
local text_margin = wibox.widget { widget = wibox.widget.textbox, text = " " }

-- Create a text widget for memory usage
local mem_widget = wibox.widget {
  widget = wibox.widget.textbox,
  text = "[Loading...]"   -- Initial text while loading
}

-- Function to update the memory widget
local function sync_mem_widget()
  awful.spawn.easy_async("free -h", function(stdout, stderr, reason, exit_code)
    if exit_code ~= 0 then
      print("Error executing command: " .. reason .. " | stderr: " .. stderr)
      mem_widget.text = "[Error]"
    else
      -- Split the output into lines
      local lines = {}
      for line in stdout:gmatch("[^\r\n]+") do
        table.insert(lines, line)
      end

      -- Get the second line (which contains memory info)
      local mem_info = lines[2]       -- This is the line for physical memory

      -- Extract the used memory (3rd column)
      local mem_used = mem_info:match("%S+%s+%S+%s+(%S+)")
      if mem_used and mem_used ~= "" then
        mem_widget.text = "[" .. mem_used .. "]"
      else
        mem_widget.text = "[N/A]"
      end
    end
  end)
end

-- Update the widget immediately
sync_mem_widget()

-- Create a timer to update the widget every 5 seconds
gears.timer {
  timeout = 5,
  autostart = true,
  callback = sync_mem_widget,
}



cpu_widget = wibox.widget.textbox()
-- vicious.register(cpu_widget, vicious.widgets.cpu, "[CPU: $1%]", 1)

-- Create battery widget
local battery_widget = wibox.widget.textbox()
-- Function to get battery percentage using acpi
local function update_battery()
    local f = io.popen("acpi -b 2>/dev/null")
    if f then
        local output = f:read("*all")
        f:close()
        -- Extract percentage from acpi output
        local percentage = output:match("(%d+)%%")
        if percentage then
            battery_widget:set_text("[" .. percentage .. "% BAT]")
        else
            battery_widget:set_text("[N/A BAT]")
        end
    else
        battery_widget:set_text("[N/A] BAT")
    end
end

gears.timer {
    timeout = 10,
    autostart = true,
    callback = update_battery,
}

-- Initial update
update_battery()

-- Create network widget
local net_widget = wibox.widget.textbox()

-- Closure variables for speed calculation
local prev_interface = nil
local prev_rx_bytes = nil
local prev_tx_bytes = nil
local prev_time = nil
local measuring = false

-- Function to get network status and speeds
local function update_network()
    -- Get default route interface
    local f = io.popen("ip route get 1.1.1.1 2>/dev/null | grep -oP 'dev \\K\\S+'")
    if not f then
        net_widget:set_text("[NET: err]")
        prev_interface = nil
        prev_rx_bytes = nil
        prev_tx_bytes = nil
        prev_time = nil
        measuring = false
        return
    end
    
    local interface = f:read("*l")
    f:close()
    
    if not interface then
        net_widget:set_text("[NET: none]")
        prev_interface = nil
        prev_rx_bytes = nil
        prev_tx_bytes = nil
        prev_time = nil
        measuring = false
        return
    end
    
    -- Check if interface is up
    local f2 = io.popen("ip link show " .. interface .. " 2>/dev/null | grep -q 'state UP' && echo 'up' || echo 'down'")
    if not f2 then
        net_widget:set_text("[NET: err]")
        prev_interface = nil
        prev_rx_bytes = nil
        prev_tx_bytes = nil
        prev_time = nil
        measuring = false
        return
    end
    
    local status = f2:read("*l")
    f2:close()
    
    if status ~= "up" then
        net_widget:set_text("[NET: down]")
        prev_interface = nil
        prev_rx_bytes = nil
        prev_tx_bytes = nil
        prev_time = nil
        measuring = false
        return
    end
    
    -- Interface is up, get current byte counts
    local current_time = os.time()
    local rx_file = io.open("/sys/class/net/" .. interface .. "/statistics/rx_bytes", "r")
    local tx_file = io.open("/sys/class/net/" .. interface .. "/statistics/tx_bytes", "r")
    
    if not rx_file or not tx_file then
        net_widget:set_text("[NET: err]")
        if rx_file then rx_file:close() end
        if tx_file then tx_file:close() end
        prev_interface = nil
        prev_rx_bytes = nil
        prev_tx_bytes = nil
        prev_time = nil
        measuring = false
        return
    end
    
    local current_rx = tonumber(rx_file:read("*a"))
    local current_tx = tonumber(tx_file:read("*a"))
    rx_file:close()
    tx_file:close()
    
    if not current_rx or not current_tx then
        net_widget:set_text("[NET: err]")
        prev_interface = nil
        prev_rx_bytes = nil
        prev_tx_bytes = nil
        prev_time = nil
        measuring = false
        return
    end
    
    -- Reset previous values if interface changed
    if prev_interface ~= interface then
        prev_interface = interface
        prev_rx_bytes = current_rx
        prev_tx_bytes = current_tx
        prev_time = current_time
        measuring = true
        net_widget:set_text("[NET: ...]")
        return
    end
    
    -- Calculate speeds (MB/s = bytes / seconds / 1048576)
    local time_diff = current_time - prev_time
    if time_diff <= 0 then
        -- Not enough time elapsed, keep previous display
        return
    end
    
    local rx_diff = current_rx - prev_rx_bytes
    local tx_diff = current_tx - prev_tx_bytes
    
    -- Debug: print raw values
    -- print("DEBUG: time_diff=" .. time_diff .. " rx_diff=" .. rx_diff .. " tx_diff=" .. tx_diff)
    
    -- Safeguard against counter reset or negative values
    if rx_diff < 0 then rx_diff = 0 end
    if tx_diff < 0 then tx_diff = 0 end
    
    local down_mbs = rx_diff / time_diff / 1048576
    local up_mbs = tx_diff / time_diff / 1048576
    
    -- Debug: print calculated MB/s
    -- print("DEBUG: down_mbs=" .. down_mbs .. " up_mbs=" .. up_mbs)
    
    -- Cap unrealistic speeds (e.g., > 1000 MB/s)
    if down_mbs > 1000 then down_mbs = 1000 end
    if up_mbs > 1000 then up_mbs = 1000 end
    
    -- Update previous values
    prev_rx_bytes = current_rx
    prev_tx_bytes = current_tx
    prev_time = current_time
    
    -- Format speeds with appropriate units
    local down_str, up_str, unit
    local threshold = 0.1  -- 0.1 MB/s = ~100 KB/s
    
    -- Use KB/s if either speed is below threshold (simpler)
    if down_mbs < threshold or up_mbs < threshold then
        -- Use KB/s for both
        local down_kbs = rx_diff / time_diff / 1024
        local up_kbs = tx_diff / time_diff / 1024
        down_str = string.format("%.1f", down_kbs)
        up_str = string.format("%.1f", up_kbs)
        unit = "KB/s"
    else
        -- Use MB/s for both
        down_str = string.format("%.1f", down_mbs)
        up_str = string.format("%.1f", up_mbs)
        unit = "MB/s"
    end
    
    -- Determine prefix for Ethernet interfaces
    local prefix = ""
    if interface:match("^eth") or interface:match("^en") then
        prefix = "E: "
    end
    
    -- Set widget text
    net_widget:set_text("[" .. prefix .. "↓" .. down_str .. " ↑" .. up_str .. " " .. unit .. "]")
end

gears.timer {
    timeout = 5,
    autostart = true,
    callback = update_network,
}

-- Initial update
update_network()



-- floating windows titlebars
client.connect_signal("property::floating", function(c)
  if c.floating then
    awful.titlebar.show(c)
    c.ontop = true
  else
    awful.titlebar.hide(c)
    c.ontop = false
  end
end)

-- Volume control function
local volume_notification = nil

local function volume_control(action)
  local cmd
  local description
  
  if action == "up" then
    cmd = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
    description = "Volume up"
  elseif action == "down" then
    cmd = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
    description = "Volume down"
  elseif action == "mute" then
    cmd = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
    description = "Toggle mute"
  else
    return
  end
  
  awful.spawn.easy_async_with_shell(cmd .. " && wpctl get-volume @DEFAULT_AUDIO_SINK@", function(stdout, stderr, reason, exit_code)
    if exit_code ~= 0 then
      naughty.notify({
        preset = naughty.config.presets.critical,
        title = "Volume Error",
        text = "Failed to adjust volume: " .. (stderr or reason)
      })
      return
    end
    
    -- Parse volume output
    local volume_text = stdout:gsub("\n", "")
    local is_muted = volume_text:match("%[MUTED%]")
    local volume_value = volume_text:match("Volume:%s*(%d+%.?%d*)") or "0"
    
    -- Convert to percentage (wpctl outputs 1.0 = 100%)
    local volume_percent = math.floor(tonumber(volume_value) * 100 + 0.5)
    
    -- Create notification text
    local notification_text
    if is_muted then
      notification_text = "Muted"
    else
      notification_text = "Volume: " .. volume_percent .. "%"
    end
    
    -- Replace existing volume notification instead of creating new one
    if volume_notification then
      naughty.destroy(volume_notification)
      volume_notification = nil
    end
    
    -- Show notification
    volume_notification = naughty.notify({
      preset = naughty.config.presets.normal,
      title = description,
      text = notification_text,
      timeout = 2
    })
  end)
end

-- This is used later as the default terminal and editor to run.
terminal = "kitty"
editor = os.getenv("EDITOR")
editor_cmd = terminal .. " -e " .. editor

beautiful.useless_gap = 5
beautiful.gap_single_client = true
awesome.set_preferred_icon_size(32)

-- Default modkey.
-- Usually, Mod4 is the key with a logo between Control and Alt.
-- If you do not like this or do not have such a key,
-- I suggest you to remap Mod4 to another key using xmodmap or other tools.
-- However, you can use another modifier like Mod1, but it may interact with others.
modkey = "Mod4"

-- Table of layouts to cover with awful.layout.inc, order matters.
awful.layout.layouts = {
  awful.layout.suit.spiral,
  awful.layout.suit.tile,
}
-- }}}

-- {{{ Menu
-- Create a launcher widget and a main menu
myawesomemenu = {
  { "hotkeys",     function() hotkeys_popup.show_help(nil, awful.screen.focused()) end },
  { "manual",      terminal .. " -e man awesome" },
  { "edit config", editor_cmd .. " " .. awesome.conffile },
  { "restart",     awesome.restart },
  { "quit",        function() awesome.quit() end },
}

mymainmenu = awful.menu({
  items = { { "awesome", myawesomemenu, beautiful.awesome_icon },
    { "open terminal", terminal }
  }
})

mylauncher = awful.widget.launcher({
  image = beautiful.awesome_icon,
  menu = mymainmenu
})

-- Menubar configuration
menubar.utils.terminal = terminal -- Set the terminal for applications that require it
-- }}}

-- Keyboard map indicator and switcher
mykeyboardlayout = awful.widget.keyboardlayout()

-- {{{ /wiWibar
-- Create a textclock widget
mytextclock = wibox.widget.textclock("%a %b %d %H:%M:%S", 1)
-- Create a wibox for each screen and add it
local taglist_buttons = gears.table.join(
  awful.button({}, 1, function(t) t:view_only() end),
  awful.button({ modkey }, 1, function(t)
    if client.focus then
      client.focus:move_to_tag(t)
    end
  end),
  awful.button({}, 3, awful.tag.viewtoggle),
  awful.button({ modkey }, 3, function(t)
    if client.focus then
      client.focus:toggle_tag(t)
    end
  end),
  awful.button({}, 4, function(t) awful.tag.viewnext(t.screen) end),
  awful.button({}, 5, function(t) awful.tag.viewprev(t.screen) end)
)

local tasklist_buttons = gears.table.join(
  awful.button({}, 1, function(c)
    if c == client.focus then
      c.minimized = true
    else
      c:emit_signal(
        "request::activate",
        "tasklist",
        { raise = true }
      )
    end
  end),
  awful.button({}, 3, function()
    awful.menu.client_list({ theme = { width = 250 } })
  end),
  awful.button({}, 4, function()
    awful.client.focus.byidx(1)
  end),
  awful.button({}, 5, function()
    awful.client.focus.byidx(-1)
  end))

local function set_wallpaper(s)
  gears.wallpaper.set("#000000")
end
-- Re-set wallpaper when a screen's geometry changes (e.g. different resolution)
screen.connect_signal("property::geometry", set_wallpaper)

awful.screen.connect_for_each_screen(function(s)
  -- Wallpaper
  set_wallpaper(s)

  -- Each screen has its own tag table.
  awful.tag({ "1", "2", "3", "4", "5", "6", "7", "8", "9" }, s, awful.layout.layouts[1])

  -- Create a promptbox for each screen
  s.mypromptbox = awful.widget.prompt()
  -- Create an imagebox widget which will contain an icon indicating which layout we're using.
  -- We need one layoutbox per screen.
  s.mylayoutbox = awful.widget.layoutbox(s)
  s.mylayoutbox:buttons(gears.table.join(
    awful.button({}, 1, function() awful.layout.inc(1) end),
    awful.button({}, 3, function() awful.layout.inc(-1) end),
    awful.button({}, 4, function() awful.layout.inc(1) end),
    awful.button({}, 5, function() awful.layout.inc(-1) end)))
  -- Create a taglist widget
  s.mytaglist = awful.widget.taglist {
    screen  = s,
    filter  = awful.widget.taglist.filter.all,
    buttons = taglist_buttons
  }

  -- Create a tasklist widget
  s.mytasklist = awful.widget.tasklist {
    screen  = s,
    filter  = awful.widget.tasklist.filter.currenttags,
    buttons = tasklist_buttons
  }

  -- Create the wibox
  s.mywibox = awful.wibar({ position = "top", screen = s })
  client.connect_signal("property::fullscreen", function(c)
    if c.fullscreen then
      -- Remove the titlebar
      awful.titlebar.hide(c)
      c:geometry(c.screen.geometry)
    else
      -- Show the titlebar again
      awful.titlebar.show(c)
    end
  end)

  -- Add widgets to the wibox
  s.mywibox:setup {
    layout = wibox.layout.align.horizontal,
    {     -- Left widgets
      layout = wibox.layout.fixed.horizontal,
      -- mylauncher,
      text_margin,
      s.mytaglist,
      s.mylayoutbox,
      s.mypromptbox,
    },
    s.mytasklist,     -- Middle widget
    {                 -- Right widgets
      layout = wibox.layout.fixed.horizontal,
       text_margin,
       wibox.widget.systray(),
       text_margin,
       net_widget,
       text_margin,
       cpu_widget,
       text_margin,
       battery_widget,
       text_margin,
       mem_widget,
       text_margin,
       mytextclock,
       text_margin,
    },
  }
end)
-- }}}

-- {{{ Mouse bindings
root.buttons(gears.table.join(
  awful.button({}, 3, function() mymainmenu:toggle() end),
  awful.button({}, 4, awful.tag.viewnext),
  awful.button({}, 5, awful.tag.viewprev)
))
-- }}}



-- {{{ Key bindings
globalkeys = gears.table.join(
  awful.key({ modkey, }, "s", hotkeys_popup.show_help,
    { description = "show help", group = "awesome" }),
  awful.key({ modkey, }, "Left", awful.tag.viewprev,
    { description = "view previous", group = "tag" }),
  awful.key({ modkey, }, "Right", awful.tag.viewnext,
    { description = "view next", group = "tag" }),
  awful.key({ modkey, }, "Escape", awful.tag.history.restore,
    { description = "go back", group = "tag" }),

  awful.key({ modkey, }, "j",
    function()
      awful.client.focus.byidx(1)
    end,
    { description = "focus next by index", group = "client" }
  ),
  awful.key({ modkey, }, "k",
    function()
      awful.client.focus.byidx(-1)
    end,
    { description = "focus previous by index", group = "client" }
  ),
  awful.key({ modkey, }, "w", function() mymainmenu:show() end,
    { description = "show main menu", group = "awesome" }),

  -- Layout manipulation
  awful.key({ modkey, "Shift" }, "j", function() awful.client.swap.byidx(1) end,
    { description = "swap with next client by index", group = "client" }),
  awful.key({ modkey, "Shift" }, "k", function() awful.client.swap.byidx(-1) end,
    { description = "swap with previous client by index", group = "client" }),
  awful.key({ modkey, "Control" }, "j", function() awful.screen.focus_relative(1) end,
    { description = "focus the next screen", group = "screen" }),
  awful.key({ modkey, "Control" }, "k", function() awful.screen.focus_relative(-1) end,
    { description = "focus the previous screen", group = "screen" }),
  awful.key({ modkey, }, "u", awful.client.urgent.jumpto,
    { description = "jump to urgent client", group = "client" }),
  awful.key({ modkey, }, "Tab",
    function()
      awful.client.focus.history.previous()
      if client.focus then
        client.focus:raise()
      end
    end,
    { description = "go back", group = "client" }),

  -- Standard program
  awful.key({ modkey, }, "Return", function() awful.spawn(terminal) end,
    { description = "open a terminal", group = "launcher" }),
  awful.key({ modkey, "Shift" }, "Return", function()
      local term = awful.spawn(terminal, { floating = true, geometry = { width = 900, height = 630 } })
    end,
    { description = "open a terminal (floating)", group = "launcher" }),
  awful.key({ modkey, "Control" }, "r", awesome.restart,
    { description = "reload awesome", group = "awesome" }),
  awful.key({ modkey, "Shift" }, "q", awesome.quit,
    { description = "quit awesome", group = "awesome" }),
  awful.key({ modkey, }, "l", function() awful.tag.incmwfact(0.05) end,
    { description = "increase master width factor", group = "layout" }),
  awful.key({ modkey, }, "h", function() awful.tag.incmwfact(-0.05) end,
    { description = "decrease master width factor", group = "layout" }),
  awful.key({ modkey, "Shift" }, "h", function() awful.tag.incnmaster(1, nil, true) end,
    { description = "increase the number of master clients", group = "layout" }),
  awful.key({ modkey, "Shift" }, "l", function() awful.tag.incnmaster(-1, nil, true) end,
    { description = "decrease the number of master clients", group = "layout" }),
  awful.key({ modkey, "Control" }, "h", function() awful.tag.incncol(1, nil, true) end,
    { description = "increase the number of columns", group = "layout" }),
  awful.key({ modkey, "Control" }, "l", function() awful.tag.incncol(-1, nil, true) end,
    { description = "decrease the number of columns", group = "layout" }),
  awful.key({ modkey, }, "space", function() awful.layout.inc(1) end,
    { description = "select next", group = "layout" }),
  awful.key({ modkey, "Shift" }, "space", function() awful.layout.inc(-1) end,
    { description = "select previous", group = "layout" }),

  awful.key({ modkey, "Control" }, "n",
    function()
      local c = awful.client.restore()
      -- Focus restored client
      if c then
        c:emit_signal(
          "request::activate", "key.unminimize", { raise = true }
        )
      end
    end,
    { description = "restore minimized", group = "client" })
)
clientkeys = gears.table.join(
  awful.key({ modkey, }, "g",
    function(c)
      c.fullscreen = not c.fullscreen
      c:raise()
    end,
    { description = "toggle fullscreen", group = "client" }),
  awful.key({ modkey, "Shift" }, "c", function(c) c:kill() end,
    { description = "close", group = "client" }),
  awful.key({ modkey, "Control" }, "space", awful.client.floating.toggle,
    { description = "toggle floating", group = "client" }),
  awful.key({ modkey, "Control" }, "Return", function(c) c:swap(awful.client.getmaster()) end,
    { description = "move to master", group = "client" }),
  awful.key({ modkey, }, "o", function(c) c:move_to_screen() end,
    { description = "move to screen", group = "client" }),
  awful.key({ modkey, }, "t", function(c) c.ontop = not c.ontop end,
    { description = "toggle keep on top", group = "client" }),
  awful.key({ modkey, }, "n",
    function(c)
      -- The client currently has the input focus, so it cannot be
      -- minimized, since minimized clients can't have the focus.
      c.minimized = true
    end,
    { description = "minimize", group = "client" }),
  awful.key({ modkey, }, "m",
    function(c)
      c.maximized = not c.maximized
      c:raise()
    end,
    { description = "(un)maximize", group = "client" }),
  awful.key({ modkey, "Control" }, "m",
    function(c)
      c.maximized_vertical = not c.maximized_vertical
      c:raise()
    end,
    { description = "(un)maximize vertically", group = "client" }),
  awful.key({ modkey, "Shift" }, "m",
    function(c)
      c.maximized_horizontal = not c.maximized_horizontal
      c:raise()
    end,
    { description = "(un)maximize horizontally", group = "client" })
)

-- Bind all key numbers to tags.
-- Be careful: we use keycodes to make it work on any keyboard layout.
-- This should map on the top row of your keyboard, usually 1 to 9.
for i = 1, 9 do
  globalkeys = gears.table.join(globalkeys,
    -- View tag only.
    awful.key({ modkey }, "#" .. i + 9,
      function()
        local screen = awful.screen.focused()
        local tag = screen.tags[i]
        if tag then
          tag:view_only()
        end
      end,
      { description = "view tag #" .. i, group = "tag" }),
    -- Toggle tag display.
    awful.key({ modkey, "Control" }, "#" .. i + 9,
      function()
        local screen = awful.screen.focused()
        local tag = screen.tags[i]
        if tag then
          awful.tag.viewtoggle(tag)
        end
      end,
      { description = "toggle tag #" .. i, group = "tag" }),
    -- Move client to tag.
    awful.key({ modkey, "Shift" }, "#" .. i + 9,
      function()
        if client.focus then
          local tag = client.focus.screen.tags[i]
          if tag then
            client.focus:move_to_tag(tag)
          end
        end
      end,
      { description = "move focused client to tag #" .. i, group = "tag" }),
    -- Toggle tag on focused client.
    awful.key({ modkey, "Control", "Shift" }, "#" .. i + 9,
      function()
        if client.focus then
          local tag = client.focus.screen.tags[i]
          if tag then
            client.focus:toggle_tag(tag)
          end
        end
      end,
      { description = "toggle focused client on tag #" .. i, group = "tag" })
  )
end

globalkeys = gears.table.join(globalkeys,
  awful.key({ modkey, }, "p", function() awful.spawn("rofi -show drun -disable-history -show-icons") end,
    { description = "show rofi drun", group = "launcher" }),
  awful.key({ modkey, }, "r", function() awful.spawn("rofi -show run -disable-history -show-icons") end,
    { description = "show rofi run", group = "launcher" }),
  awful.key({ modkey, }, "e", function() awful.spawn("rofi -show emoji -modi emoji -emoji-mode copy") end,
    { description = "show rofi emoji", group = "launcher" }),
  awful.key({}, "XF86AudioPlay", function() awful.spawn("playerctl play-pause") end,
    { description = "play/pause media", group = "media" }),
  awful.key({}, "XF86AudioNext", function() awful.spawn("playerctl next") end,
    { description = "next media", group = "media" }),
  awful.key({}, "XF86AudioPrev", function() awful.spawn("playerctl previous") end,
    { description = "previous media", group = "media" }),
  awful.key({}, "XF86AudioRaiseVolume", function() volume_control("up") end,
    { description = "volume up", group = "media" }),
  awful.key({}, "XF86AudioLowerVolume", function() volume_control("down") end,
    { description = "volume down", group = "media" }),
  awful.key({}, "XF86AudioMute", function() volume_control("mute") end,
    { description = "toggle mute", group = "media" }),
  awful.key({}, "Print", function() awful.spawn.with_shell("flameshot screen --clipboard") end,
    { description = "screenshot", group = "screenshot" }),
  awful.key({ "Control", }, "Print", function() awful.spawn.with_shell("flameshot gui --clipboard") end,
    { description = "screenshot sel", group = "screenshot" })
)

clientbuttons = gears.table.join(
  awful.button({}, 1, function(c)
    c:emit_signal("request::activate", "mouse_click", { raise = true })
  end),
  awful.button({ modkey }, 1, function(c)
    c:emit_signal("request::activate", "mouse_click", { raise = true })
    awful.mouse.client.move(c)
  end),
  awful.button({ modkey }, 3, function(c)
    c:emit_signal("request::activate", "mouse_click", { raise = true })
    awful.mouse.client.resize(c)
  end)
)

-- Set keys
root.keys(globalkeys)
-- }}}

-- {{{ Rules
-- Rules to apply to new clients (through the "manage" signal).
awful.rules.rules = {
  -- All clients will match this rule.
  {
    rule = {},
    properties = {
      border_width = beautiful.border_width,
      border_color = beautiful.border_normal,
      focus = awful.client.focus.filter,
      raise = true,
      keys = clientkeys,
      buttons = clientbuttons,
      screen = awful.screen.preferred,
      placement = awful.placement.no_overlap + awful.placement.no_offscreen
    }
  },

  -- Floating clients.
  {
    rule_any = {
      instance = {
        "DTA",     -- Firefox addon DownThemAll.
        "copyq",   -- Includes session name in class.
        "pinentry",
      },
      class = {
        "Arandr",
        "Blueman-manager",
        "Gpick",
        "Kruler",
        "MessageWin",    -- kalarm.
        "Sxiv",
        "Tor Browser",   -- Needs a fixed window size to avoid fingerprinting by screen size.
        "Wpa_gui",
        "veromix",
        "xtightvncviewer",
        "Nemo",
        "Ark",
        "Kleopatra",
      },

      -- Note that the name property shown in xprop might be set slightly after creation of the client
      -- and the name shown there might not match defined rules here.
      name = {
        "Event Tester",   -- xev.
      },
      role = {
        "AlarmWindow",     -- Thunderbird's calendar.
        "ConfigManager",   -- Thunderbird's about:config.
        "pop-up",          -- e.g. Google Chrome's (detached) Developer Tools.
      }
    },
    properties = { floating = true }
  },

  -- Add titlebars to normal clients and dialogs
  {
    rule_any = { type = { "normal", "dialog" }
    },
    properties = { titlebars_enabled = false }
  },

  -- Set Firefox to always map on the tag named "2" on screen 1.
  -- { rule = { class = "Firefox" },
  --   properties = { screen = 1, tag = "2" } },
}
-- }}}

-- {{{ Signals
-- Signal function to execute when a new client appears.
client.connect_signal("manage", function(c)
  -- Set the windows at the slave,
  -- i.e. put it at the end of others instead of setting it master.
  if not awesome.startup then awful.client.setslave(c) end

  if awesome.startup
      and not c.size_hints.user_position
      and not c.size_hints.program_position then
    -- Prevent clients from being unreachable after screen count changes.
    awful.placement.no_offscreen(c)
  end
end)

-- Add a titlebar if titlebars_enabled is set to true in the rules.
client.connect_signal("request::titlebars", function(c)
  -- buttons for the titlebar
  local buttons = gears.table.join(
    awful.button({}, 1, function()
      c:emit_signal("request::activate", "titlebar", { raise = true })
      awful.mouse.client.move(c)
    end),
    awful.button({}, 3, function()
      c:emit_signal("request::activate", "titlebar", { raise = true })
      awful.mouse.client.resize(c)
    end)
  )

  awful.titlebar(c):setup {
    {     -- Left
      awful.titlebar.widget.iconwidget(c),
      buttons = buttons,
      layout  = wibox.layout.fixed.horizontal
    },
    {         -- Middle
      {       -- Title
        align  = "center",
        widget = awful.titlebar.widget.titlewidget(c)
      },
      buttons = buttons,
      layout  = wibox.layout.flex.horizontal
    },
    {     -- Right
      -- awful.titlebar.widget.floatingbutton (c),
      -- awful.titlebar.widget.maximizedbutton(c),
      awful.titlebar.widget.stickybutton(c),
      awful.titlebar.widget.ontopbutton(c),
      -- awful.titlebar.widget.closebutton    (c),
      layout = wibox.layout.fixed.horizontal()
    },
    layout = wibox.layout.align.horizontal
  }
end)

-- Enable sloppy focus, so that focus follows mouse.
client.connect_signal("mouse::enter", function(c)
  c:emit_signal("request::activate", "mouse_enter", { raise = false })
end)

client.connect_signal("focus", function(c) c.border_color = beautiful.border_focus end)
client.connect_signal("unfocus", function(c) c.border_color = beautiful.border_normal end)
-- }}}
