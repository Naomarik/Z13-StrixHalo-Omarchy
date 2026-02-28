#!/usr/bin/env bash

# Get sensor output once
sensor_output=$(sensors)

# Get CPU temperature (k10temp)
cpu_temp=$(echo "$sensor_output" | grep 'Tctl:' | awk '{print $2}' | sed 's/+//;s/°C//')

# Get GPU temperature (amdgpu)
gpu_temp=$(echo "$sensor_output" | grep 'edge:' | awk '{print $2}' | sed 's/+//;s/°C//')

# Format the output
if [ -n "$cpu_temp" ] && [ -n "$gpu_temp" ]; then
    # Round to integer
    cpu_temp_int=$(printf "%.0f" "$cpu_temp")
    gpu_temp_int=$(printf "%.0f" "$gpu_temp")

    # Determine CPU icon and color based on temperature
    if [ "$cpu_temp_int" -ge 90 ]; then
        cpu_icon="<span color='#ff4444'>󰸁</span>"  # Hot - red
    elif [ "$cpu_temp_int" -ge 80 ]; then
        cpu_icon="<span color='#ffd700'>󱃃</span>"  # Warm - yellow
    elif [ "$cpu_temp_int" -ge 70 ]; then
        cpu_icon="󱃃"  # Warm
    else
        cpu_icon="󰔏"  # Cool
    fi

    # Determine GPU icon color based on temperature
    if [ "$gpu_temp_int" -ge 90 ]; then
        gpu_icon="<span color='#ff4444'>󰾲</span>"  # Hot - red
    elif [ "$gpu_temp_int" -ge 80 ]; then
        gpu_icon="<span color='#ffd700'>󰾲</span>"  # Warm - yellow
    else
        gpu_icon="󰾲"  # Normal
    fi

    # Output JSON for waybar
    echo "{\"text\":\"${cpu_icon} ${cpu_temp_int}°C ${gpu_icon} ${gpu_temp_int}°C\", \"tooltip\":\"CPU: ${cpu_temp_int}°C\\nGPU: ${gpu_temp_int}°C\", \"class\":\"temperature\"}"
else
    echo "{\"text\":\"N/A\", \"tooltip\":\"Temperature sensors not available\"}"
fi
