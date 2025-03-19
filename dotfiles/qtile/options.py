terminal = "kitty"
# I hope this option is obvious



battery_opts = dict(
    update_interval=10,
    battery = 1,
    format = '{char} {percent:2.0%}',
    unknown_char = "?",
    discharge_char = "⚡",
    charge_char = "🔌",
    empty_char = "🪫",
    full_char = "🔋",
    notify_below = 30,
    show_short_text = False,
    low_percantage = 0.3,
    low_foreground = "b87263"    
)

groupbox_config = dict(
    active='eeeeee', 
    inactive='888888', 
    disable_drag=True, 
    this_current_screen_border='4c7bab', 
    center_aligned=True, 
    urgent_border='d53d53',
    highlight_method='line',
    highlight_color=['333333', '333333']
)

# border colors
border = dict(
    border_focus="4c7bab",
    border_normal="444444",
    border_width=4,
    margin=20
)

padding = dict(
    foreground = '222222',
    linewidth=6
)
# https://docs.qtile.org if you're unsure about options
