#!/bin/bash/

# kill startup apps
killall picom

picom &

xrandr --output DP-3 --primary --mode 1920x1080 --rate 165 --pos 0x0 --output DP-1 --mode 1920x1080 --pos 1920x0
exec awesome
