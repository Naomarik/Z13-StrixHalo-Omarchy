#!/bin/bash

# Read the amdgpu PPT sensor from hwmon instead of polling SMU via ryzenadj -i.
for hwmon in /sys/class/hwmon/hwmon*; do
    [[ -r "$hwmon/name" && "$(<"$hwmon/name")" == "amdgpu" ]] || continue
    [[ -r "$hwmon/power1_average" ]] || continue

    microwatts=$(<"$hwmon/power1_average")
    value=$(( (microwatts + 500000) / 1000000 ))
    echo "{\"text\":\" ${value}W\",\"tooltip\":\"PPT power from amdgpu hwmon: ${value}W\"}"
    exit 0
done

if [[ -r /sys/class/drm/card1/device/hwmon/hwmon7/power1_average ]]; then
    microwatts=$(</sys/class/drm/card1/device/hwmon/hwmon7/power1_average)
    value=$(( (microwatts + 500000) / 1000000 ))
    echo "{\"text\":\" ${value}W\",\"tooltip\":\"PPT power from amdgpu hwmon: ${value}W\"}"
else
    echo "{\"text\":\" N/A\",\"tooltip\":\"Power data unavailable\"}"
fi
