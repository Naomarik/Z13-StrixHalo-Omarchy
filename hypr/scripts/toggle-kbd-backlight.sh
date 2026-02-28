#!/bin/bash

current=$(brightnessctl -d asus::kbd_backlight get)
max=3

if [ "$current" -ge "$max" ]; then
    brightnessctl -d asus::kbd_backlight set 0
    brightnessctl -d asus::kbd_backlight_1 set 0
else
    next=$((current + 1))
    brightnessctl -d asus::kbd_backlight set $next
    brightnessctl -d asus::kbd_backlight_1 set $next
fi
